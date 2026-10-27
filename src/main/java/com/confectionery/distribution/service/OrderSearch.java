package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import jakarta.persistence.EntityManager;
import jakarta.persistence.TypedQuery;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.*;

/**
 * Список заказов с фильтрами и страницами. Фильтры и подсчёт — запросом к базе (заказов тысячи), компания —
 * фильтром Hibernate, как везде.
 */
@Service
@RequiredArgsConstructor
public class OrderSearch {

    /** Сколько строк можно показать на странице. */
    public static final List<Integer> SIZES = List.of(25, 50, 100, 200);
    public static final int DEFAULT_SIZE = 50;

    private final EntityManager em;

    /**
     * Условия списка. Даты — доставки, включительно, null — без границы. agents и regions — любые из
     * выбранных; expeditor: null — любой, {@link #NO_EXPEDITOR} — ещё не в рейсе, иначе id экспедитора.
     */
    public record Filter(LocalDate from, LocalDate to, List<Long> agents, List<Long> regions, Long expeditor,
                         OrderStatus status, String q) {
        public Filter {
            agents = agents == null ? List.of() : agents;
            regions = regions == null ? List.of() : regions;
        }
    }

    public static final long NO_EXPEDITOR = 0L;

    /** Страница списка: строки, сколько всего, сумма всех найденных, разбивка по статусам (без фильтра статуса). */
    public record Page(List<Order> rows, long total, long sum, Map<OrderStatus, Long> counts, int page, int size) {
        public int pages() {
            return (int) Math.max(1, (total + size - 1) / size);
        }

        /** Номер первой строки на странице (с 1). */
        public long first() {
            return total == 0 ? 0 : (long) (page - 1) * size + 1;
        }

        public long last() {
            return Math.min(total, (long) page * size);
        }

        /** Номера страниц для ссылок: первая, последняя и две вокруг текущей; 0 — пропуск «…». */
        public List<Integer> around() {
            List<Integer> out = new ArrayList<>();
            int n = pages();
            for (int i = 1; i <= n; i++) {
                if (i == 1 || i == n || Math.abs(i - page) <= 2) out.add(i);
                else if (!out.isEmpty() && out.get(out.size() - 1) != 0) out.add(0);
            }
            return out;
        }
    }

    private static final String FROM = " from Order o join o.outlet ot left join o.agent a";

    /** Все найденные заказы, не больше limit (для карты списка), — новые доставки первыми. */
    public List<Order> all(Filter f, int limit) {
        Map<String, Object> params = new HashMap<>();
        return query("select o" + FROM + where(f, params, true) + " order by o.deliveryDate desc, o.id desc", Order.class, params)
                .setMaxResults(limit).getResultList();
    }

    public Page find(Filter f, int page, int size) {
        int s = SIZES.contains(size) ? size : DEFAULT_SIZE;
        Map<String, Object> params = new HashMap<>();
        String from = FROM;
        String where = where(f, params, true);

        long total = query("select count(o)" + from + where, Long.class, params).getSingleResult();
        int pages = (int) Math.max(1, (total + s - 1) / s);
        int p = Math.max(1, Math.min(page, pages));
        List<Order> rows = query("select o" + from + where + " order by o.deliveryDate desc, o.createdAt desc, o.id desc", Order.class, params)
                .setFirstResult((p - 1) * s).setMaxResults(s).getResultList();
        Long sum = query("select coalesce(sum(l.qty * l.price - coalesce(l.discount, 0)), 0) from OrderLine l where l.order.id in"
                + " (select o.id" + from + where + ")", Long.class, params).getSingleResult();

        Map<String, Object> noStatus = new HashMap<>();
        String whereNoStatus = where(f, noStatus, false);
        Map<OrderStatus, Long> counts = new EnumMap<>(OrderStatus.class);
        for (Object[] r : query("select o.status, count(o)" + from + whereNoStatus + " group by o.status", Object[].class, noStatus).getResultList())
            counts.put((OrderStatus) r[0], (Long) r[1]);
        return new Page(rows, total, sum == null ? 0 : sum, counts, p, s);
    }

    private String where(Filter f, Map<String, Object> params, boolean withStatus) {
        List<String> w = new ArrayList<>();
        if (f.from() != null) {
            w.add("o.deliveryDate >= :from");
            params.put("from", f.from());
        }
        if (f.to() != null) {
            w.add("o.deliveryDate <= :to");
            params.put("to", f.to());
        }
        if (!f.agents().isEmpty()) {
            w.add("a.id in :agents");
            params.put("agents", f.agents());
        }
        if (!f.regions().isEmpty()) {
            // филиал = регион маршрута, на котором стоит магазин
            w.add("exists (select 1 from RouteOutlet ro where ro.outlet = ot and ro.route.region.id in :regions)");
            params.put("regions", f.regions());
        }
        if (f.expeditor() != null && f.expeditor() == NO_EXPEDITOR) {
            w.add("not exists (select 1 from TripOrder t where t.order = o)");
        } else if (f.expeditor() != null) {
            w.add("exists (select 1 from TripOrder t where t.order = o and t.trip.expeditor.id = :exp)");
            params.put("exp", f.expeditor());
        }
        if (withStatus && f.status() != null) {
            w.add("o.status = :status");
            params.put("status", f.status());
        }
        if (f.q() != null && !f.q().isBlank()) {
            w.add("(lower(o.number) like :q or lower(ot.name) like :q or lower(coalesce(a.name, '')) like :q)");
            params.put("q", "%" + f.q().strip().toLowerCase(Locale.ROOT) + "%");
        }
        return w.isEmpty() ? "" : " where " + String.join(" and ", w);
    }

    private <T> TypedQuery<T> query(String jpql, Class<T> type, Map<String, Object> params) {
        TypedQuery<T> q = em.createQuery(jpql, type);
        params.forEach(q::setParameter);
        return q;
    }
}
