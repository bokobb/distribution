package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.OrderStatus;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

/**
 * Что торговый видит о магазине кроме долга: на карте и в списке — когда в магазине последний раз были, средний
 * заказ и с какого дня он в базе (stats — для всех магазинов компании разом, в данных агента); в карточке — что
 * магазин берёт (средний заказ, сколько заказов за 8 недель, доля возвратов и их частая причина, товар, который
 * перестал брать) и история визитов с заказами и возвратами. Запросы — прямо по таблицам, компания — явно.
 */
@Service
@RequiredArgsConstructor
public class OutletCardService {

    /** За сколько дней считаются средний заказ, возвраты и история. */
    static final int DAYS = 90;
    /** Товар «перестал брать», если его не заказывали столько дней, а другое заказывали. */
    static final int STOPPED_DAYS = 21;
    static final int HISTORY = 10;

    private static final String LIVE = "o.status not in ('CANCELLED', 'REFUSED')";

    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** lastVisit — день последнего визита любого торгового; avgOrder — средний заказ за 90 дней, ₸. */
    public record StatDto(Long outletId, LocalDate lastVisit, long avgOrder, LocalDate createdOn) {
    }

    /**
     * kind — ORDER или NO_ORDER. У заказа returnTotal и returnReason — что забрал экспедитор, а пока не забрал — что
     * записал торговый; reason — почему без заказа.
     */
    public record HistoryDto(LocalDateTime at, String kind, long orderTotal, long returnTotal, String returnReason,
                             String status, String statusLabel, String reason) {
    }

    /**
     * orders8w — заказов за 8 недель; ordered и returned — сумма заказов и возвратов за 90 дней (доля возвратов),
     * returnReason — причина большей части возвратов; stopped — товар, который магазин брал, но перестал, и с какого дня.
     */
    public record CardDto(Long outletId, LocalDate createdOn, long avgOrder, int orders8w, long ordered, long returned,
                          String returnReason, String stopped, LocalDate stoppedSince, List<HistoryDto> history) {
    }

    @Transactional(readOnly = true)
    public List<StatDto> stats(Long companyId) {
        LocalDate today = LocalDate.now(clock);
        Map<Long, LocalDate> visits = new HashMap<>();
        jdbc.query("select outlet_id, max(started_at) at from visits where company_id = ? group by outlet_id",
                rs -> {
                    visits.put(rs.getLong("outlet_id"), rs.getTimestamp("at").toLocalDateTime().toLocalDate());
                }, companyId);
        Map<Long, Long> avg = new HashMap<>();
        jdbc.query("""
                select o.outlet_id, round(avg(t.total)) avg
                from orders o join (select order_id, sum(qty * price - coalesce(discount, 0)) total
                                    from order_items where company_id = ? group by order_id) t on t.order_id = o.id
                where o.company_id = ? and o.created_at >= ? and %s
                group by o.outlet_id""".formatted(LIVE), rs -> {
            avg.put(rs.getLong("outlet_id"), rs.getLong("avg"));
        }, companyId, companyId, today.minusDays(DAYS).atStartOfDay());
        return jdbc.query("select id, created_on from outlets where company_id = ? and status <> 'CLOSED' order by id",
                (rs, i) -> {
                    long id = rs.getLong("id");
                    return new StatDto(id, visits.get(id), avg.getOrDefault(id, 0L), rs.getDate("created_on").toLocalDate());
                }, companyId);
    }

    /** Карточка магазина компании; чужой компании или закрытого нет — пусто. */
    @Transactional(readOnly = true)
    public Optional<CardDto> card(Long companyId, Long outletId) {
        List<LocalDate> created = jdbc.query("select created_on from outlets where company_id = ? and id = ? and status <> 'CLOSED'",
                (rs, i) -> rs.getDate("created_on").toLocalDate(), companyId, outletId);
        if (created.isEmpty()) return Optional.empty();
        LocalDate today = LocalDate.now(clock);
        LocalDateTime from = today.minusDays(DAYS).atStartOfDay();

        List<long[]> orders = jdbc.query("""
                select o.created_at, (select coalesce(sum(qty * price - coalesce(discount, 0)), 0)
                                      from order_items i where i.order_id = o.id) total
                from orders o where o.company_id = ? and o.outlet_id = ? and o.created_at >= ? and %s""".formatted(LIVE),
                (rs, i) -> new long[]{rs.getTimestamp("created_at").toLocalDateTime().toLocalDate().toEpochDay(), rs.getLong("total")},
                companyId, outletId, from);
        long ordered = orders.stream().mapToLong(o -> o[1]).sum();
        long avgOrder = orders.isEmpty() ? 0 : Math.round((double) ordered / orders.size());
        long weeks8 = today.minusWeeks(8).toEpochDay();
        int orders8w = (int) orders.stream().filter(o -> o[0] > weeks8).count();

        long returned = 0;
        String returnReason = null;
        for (Map<String, Object> r : jdbc.queryForList("""
                select ri.reason, sum(ri.qty * ri.price) total
                from returns r join return_items ri on ri.return_id = r.id
                where r.company_id = ? and r.outlet_id = ? and r.return_date >= ?
                group by ri.reason order by total desc""", companyId, outletId, from.toLocalDate())) {
            if (returnReason == null) returnReason = (String) r.get("reason");
            returned += ((Number) r.get("total")).longValue();
        }

        String stopped = null;
        LocalDate stoppedSince = null;
        for (Map<String, Object> r : jdbc.queryForList("""
                with o as (select o.id, o.created_at from orders o
                           where o.company_id = ? and o.outlet_id = ? and o.created_at >= ? and %s),
                     p as (select i.product_id, count(*) n, max(o.created_at) last
                           from o join order_items i on i.order_id = o.id group by i.product_id)
                select pr.name, p.last from p join products pr on pr.id = p.product_id
                where p.n >= 2 and p.last < ? and p.last < (select max(created_at) from o)
                order by p.n desc, p.last desc limit 1""".formatted(LIVE),
                companyId, outletId, from, today.minusDays(STOPPED_DAYS).atStartOfDay())) {
            stopped = (String) r.get("name");
            stoppedSince = ((Timestamp) r.get("last")).toLocalDateTime().toLocalDate();
        }

        List<HistoryDto> history = new ArrayList<>(jdbc.query("""
                select o.created_at, o.status,
                       (select coalesce(sum(qty * price - coalesce(discount, 0)), 0) from order_items where order_id = o.id) total,
                       (select coalesce(sum(ri.qty * ri.price), 0) from returns r join return_items ri on ri.return_id = r.id
                        where r.order_id = o.id) back,
                       (select ri.reason from returns r join return_items ri on ri.return_id = r.id where r.order_id = o.id
                        group by ri.reason order by sum(ri.qty * ri.price) desc limit 1) back_reason,
                       (select coalesce(sum(qty * price), 0) from order_return_items where order_id = o.id) plan,
                       (select reason from order_return_items where order_id = o.id
                        group by reason order by sum(qty * price) desc limit 1) plan_reason
                from orders o where o.company_id = ? and o.outlet_id = ? and o.created_at >= ?
                order by o.created_at desc limit ?""", (rs, i) -> {
            OrderStatus st = OrderStatus.valueOf(rs.getString("status"));
            boolean taken = rs.getLong("back") > 0;
            return new HistoryDto(rs.getTimestamp("created_at").toLocalDateTime(), "ORDER", rs.getLong("total"),
                    taken ? rs.getLong("back") : rs.getLong("plan"), taken ? rs.getString("back_reason") : rs.getString("plan_reason"),
                    st.name(), st.getLabel(), null);
        }, companyId, outletId, from, HISTORY));
        history.addAll(jdbc.query("""
                select started_at, refuse_reason from visits
                where company_id = ? and outlet_id = ? and result = 'NO_ORDER' and started_at >= ?
                order by started_at desc limit ?""", (rs, i) -> new HistoryDto(rs.getTimestamp("started_at").toLocalDateTime(),
                "NO_ORDER", 0, 0, null, null, null, rs.getString("refuse_reason")), companyId, outletId, from, HISTORY));
        history.sort(Comparator.comparing(HistoryDto::at).reversed());

        return Optional.of(new CardDto(outletId, created.get(0), avgOrder, orders8w, ordered, returned, returnReason,
                stopped, stoppedSince, List.copyOf(history.subList(0, Math.min(HISTORY, history.size())))));
    }
}
