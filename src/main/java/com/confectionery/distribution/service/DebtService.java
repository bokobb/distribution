package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Outlet;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.stereotype.Service;

import java.sql.Array;
import java.time.Clock;
import java.time.LocalDate;
import java.util.*;

/**
 * Долг магазина не хранится, а считается: начальный долг + доставлено − оплачено − возвращено.
 *
 * <p>Просрочка — по принципу «первым пришёл — первым погашен»: оплаты и возвраты гасят самые старые
 * отгрузки (и начальный долг), просрочено то, что осталось непогашенным и у чего прошла отсрочка
 * магазина. Начальный долг отсчитывает отсрочку от своей даты (as_of).
 *
 * <p>Считается сразу для списка магазинов — несколькими запросами на весь список. Запросы — по id
 * магазинов, которые уже прошли фильтр компании, поэтому чужое сюда не попадёт.
 */
@Service
@RequiredArgsConstructor
public class DebtService {

    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** Отгрузка (или начальный долг) на дату. */
    public record Debit(LocalDate date, long amount) {
    }

    /** overdueDays — сколько дней просрочена самая старая непогашенная отгрузка. */
    public record Balance(long debt, long overdue, int overdueDays) {
    }

    /** Заполняет у магазинов долг, просрочку и последнюю оплату. */
    public void fill(Collection<Outlet> outlets) {
        if (outlets.isEmpty()) return;
        Long[] ids = outlets.stream().map(Outlet::getId).toArray(Long[]::new);
        Map<Long, List<Debit>> debits = new HashMap<>();
        Map<Long, Long> credits = new HashMap<>();
        Map<Long, Object[]> last = new HashMap<>();

        query("select outlet_id, as_of, amount from outlet_opening_debts where outlet_id = any(?)", ids, rs -> {
            long amount = rs.getLong(3);
            if (amount > 0) debits.computeIfAbsent(rs.getLong(1), k -> new ArrayList<>()).add(new Debit(rs.getDate(2).toLocalDate(), amount));
            else credits.merge(rs.getLong(1), -amount, Long::sum); // переплата
        });
        query("""
                select o.outlet_id, cast(d.delivered_at as date), sum(di.qty * di.price)
                from deliveries d
                join orders o on o.id = d.order_id
                join delivery_items di on di.delivery_id = d.id
                where o.outlet_id = any(?) and d.status <> 'REFUSED'
                group by o.outlet_id, cast(d.delivered_at as date)""", ids,
                rs -> debits.computeIfAbsent(rs.getLong(1), k -> new ArrayList<>()).add(new Debit(rs.getDate(2).toLocalDate(), rs.getLong(3))));
        query("select outlet_id, sum(amount) from payments where outlet_id = any(?) group by outlet_id", ids,
                rs -> credits.merge(rs.getLong(1), rs.getLong(2), Long::sum));
        query("""
                select r.outlet_id, sum(ri.qty * ri.price)
                from returns r join return_items ri on ri.return_id = r.id
                where r.outlet_id = any(?) group by r.outlet_id""", ids,
                rs -> credits.merge(rs.getLong(1), rs.getLong(2), Long::sum));
        query("""
                select distinct on (outlet_id) outlet_id, paid_at, amount
                from payments where outlet_id = any(?) order by outlet_id, paid_at desc""", ids,
                rs -> last.put(rs.getLong(1), new Object[]{rs.getTimestamp(2).toLocalDateTime().toLocalDate(), rs.getLong(3)}));

        LocalDate today = LocalDate.now(clock);
        for (Outlet o : outlets) {
            Balance b = balance(debits.getOrDefault(o.getId(), List.of()), credits.getOrDefault(o.getId(), 0L), o.getPaymentDays(), today);
            o.setDebt(b.debt()).setOverdue(b.overdue()).setOverdueDays(b.overdueDays());
            Object[] l = last.get(o.getId());
            o.setLastPaymentDate(l == null ? null : (LocalDate) l[0]).setLastPaymentSum(l == null ? 0 : (Long) l[1]);
        }
    }

    public void fill(Outlet outlet) {
        fill(List.of(outlet));
    }

    /**
     * Долг = отгружено − погашено (минус — переплата). Погашения закрывают отгрузки по порядку дат;
     * непогашенный остаток отгрузки просрочен, если дата + отсрочка уже прошла.
     */
    public static Balance balance(List<Debit> debits, long credit, int paymentDays, LocalDate today) {
        List<Debit> sorted = new ArrayList<>(debits);
        sorted.sort(Comparator.comparing(Debit::date));
        long total = 0, left = credit, overdue = 0;
        int days = 0;
        for (Debit d : sorted) {
            total += d.amount();
            long covered = Math.min(left, d.amount());
            left -= covered;
            long rest = d.amount() - covered;
            LocalDate due = d.date().plusDays(paymentDays);
            if (rest > 0 && due.isBefore(today)) {
                overdue += rest;
                days = Math.max(days, (int) java.time.temporal.ChronoUnit.DAYS.between(due, today));
            }
        }
        return new Balance(total - credit, overdue, days);
    }

    private void query(String sql, Long[] ids, RowCallbackHandler row) {
        jdbc.query(sql, ps -> {
            Array arr = ps.getConnection().createArrayOf("bigint", ids);
            ps.setArray(1, arr);
        }, row);
    }
}
