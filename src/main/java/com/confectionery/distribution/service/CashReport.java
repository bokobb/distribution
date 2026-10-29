package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.ShortageDecision;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * «Касса и недостачи»: сколько экспедиторы получили наличными по рейсам и сколько сдали, недостачи и что по ним
 * решили. Рейс относится к периоду по дате рейса. Запросы — с условием компании (null — все компании владельца).
 */
@Service
@RequiredArgsConstructor
public class CashReport {

    private static final String SCOPE = "(cast(? as bigint) is null or t.company_id = ?)";

    private final JdbcTemplate jdbc;

    /** Строка экспедитора. waiting — недостача ждёт решения директора. */
    public record Row(Long id, String name, int trips, long received, long handed, long shortage, int cases,
                      long expeditor, long writtenOff, long waiting) {
    }

    /** Случай недостачи больше нуля; decision = null — ждёт решения. */
    public record Case(Long tripId, LocalDate date, String expeditor, String trip, long amount, ShortageDecision decision,
                       String reason, String decidedBy, LocalDateTime decidedAt) {
        public String decisionText() {
            if (decision == null) return "ждёт директора";
            return decision == ShortageDecision.WRITE_OFF && reason != null ? "списано: " + reason : decision.getLabel();
        }
    }

    public record Report(List<Row> rows, List<Case> cases) {
        public Row total() {
            return new Row(null, "Итого", rows.stream().mapToInt(Row::trips).sum(), rows.stream().mapToLong(Row::received).sum(),
                    rows.stream().mapToLong(Row::handed).sum(), rows.stream().mapToLong(Row::shortage).sum(),
                    rows.stream().mapToInt(Row::cases).sum(), rows.stream().mapToLong(Row::expeditor).sum(),
                    rows.stream().mapToLong(Row::writtenOff).sum(), rows.stream().mapToLong(Row::waiting).sum());
        }

        /** Сдано от полученного, в процентах с одним знаком; null — ничего не получали. */
        public Double handedShare() {
            Row t = total();
            return t.received() == 0 ? null : Math.round(t.handed() * 1000.0 / t.received()) / 10.0;
        }
    }

    /** Отчёт за дни from..to (включительно); expeditorId = null — все экспедиторы. */
    public Report build(Long companyId, LocalDate from, LocalDate to, Long expeditorId) {
        Map<Long, Row> rows = new LinkedHashMap<>();
        jdbc.query("""
                select e.id, e.name, count(distinct t.id),
                       coalesce(sum(p.cash), 0),
                       coalesce(sum(h.counted_cash) filter (where t.status = 'CLOSED'), 0)
                from trips t
                join users e on e.id = t.expeditor_id
                left join (select trip_id, sum(amount) cash from payments where method = 'CASH' group by trip_id) p on p.trip_id = t.id
                left join cash_handovers h on h.trip_id = t.id
                where t.trip_date between ? and ? and (cast(? as bigint) is null or e.id = ?) and """ + SCOPE + """

                group by e.id, e.name order by e.name""", rs -> {
            rows.put(rs.getLong(1), new Row(rs.getLong(1), rs.getString(2), rs.getInt(3), rs.getLong(4), rs.getLong(5),
                    0, 0, 0, 0, 0));
        }, from, to, expeditorId, expeditorId, companyId, companyId);

        List<Case> cases = new ArrayList<>();
        jdbc.query("""
                select t.id, t.trip_date, e.id, e.name, t.number, -h.cash_diff, h.shortage_decision, h.shortage_reason,
                       h.decided_by, h.decided_at, t.status
                from cash_handovers h
                join trips t on t.id = h.trip_id
                join users e on e.id = h.expeditor_id
                where h.cash_diff < 0 and t.trip_date between ? and ? and (cast(? as bigint) is null or e.id = ?) and """ + SCOPE + """

                  and (h.shortage_decision is not null or t.status <> 'CLOSED')
                order by t.trip_date desc, t.id desc""", rs -> {
            String d = rs.getString(7);
            ShortageDecision decision = d == null ? null : ShortageDecision.valueOf(d);
            if (decision == ShortageDecision.TOLERANCE) return; // в пределах допуска — не случай
            long amount = rs.getLong(6);
            cases.add(new Case(rs.getLong(1), rs.getDate(2).toLocalDate(), rs.getString(4), rs.getString(5), amount,
                    decision, rs.getString(8), rs.getString(9),
                    rs.getTimestamp(10) == null ? null : rs.getTimestamp(10).toLocalDateTime()));
            rows.computeIfPresent(rs.getLong(3), (k, r) -> new Row(r.id(), r.name(), r.trips(), r.received(), r.handed(),
                    r.shortage() + amount, r.cases() + 1,
                    r.expeditor() + (decision == ShortageDecision.EXPEDITOR ? amount : 0),
                    r.writtenOff() + (decision == ShortageDecision.WRITE_OFF ? amount : 0),
                    r.waiting() + (decision == null ? amount : 0)));
        }, from, to, expeditorId, expeditorId, companyId, companyId);
        return new Report(new ArrayList<>(rows.values()), cases);
    }

    /** Долг экспедиторов по недостачам, записанным на них, — за всё время; ключ — id экспедитора. */
    public Map<Long, Long> expeditorDebts(Long companyId) {
        Map<Long, Long> out = new HashMap<>();
        jdbc.query("""
                select h.expeditor_id, sum(-h.cash_diff) from cash_handovers h join trips t on t.id = h.trip_id
                where h.shortage_decision = 'EXPEDITOR' and """ + SCOPE + " group by h.expeditor_id",
                rs -> {
                    out.put(rs.getLong(1), rs.getLong(2));
                }, companyId, companyId);
        return out;
    }
}
