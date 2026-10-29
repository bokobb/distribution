package com.confectionery.distribution.admin;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.Map;

/**
 * Счётчики в меню: что ждёт решения или действия. Разрешения — заказы на разрешении и новые магазины; магазины —
 * новые на проверке; приём кассы — рейсы, у которых пройдены все точки; склад — приходы, ждущие подтверждения.
 * Считаются прямыми запросами по компании из шапки (null — все компании).
 */
@Component
@RequiredArgsConstructor
public class MenuBadges {

    private final JdbcTemplate jdbc;
    private final Clock clock;

    public Map<String, Integer> of(Long companyId) {
        Map<String, Integer> out = new HashMap<>();
        int pendingOutlets = count("select count(*) from outlets where status = 'PENDING' and " + SCOPE, companyId);
        out.put("approvals", count("select count(*) from orders where status = 'NEEDS_APPROVAL' and " + SCOPE, companyId) + pendingOutlets);
        out.put("outlets", pendingOutlets);
        out.put("cash", count("""
                select count(*) from trips t
                where t.status <> 'CLOSED' and t.trip_date <= cast(? as date) and (cast(? as bigint) is null or t.company_id = ?)
                  and not exists (select 1 from trip_orders tor join orders o on o.id = tor.order_id
                                  where tor.trip_id = t.id and o.status = 'IN_TRIP')""", LocalDate.now(clock), companyId, companyId));
        out.put("stock", count("select count(*) from receipts where status = 'DRAFT' and " + SCOPE, companyId));
        return out;
    }

    /** Условие компании: два параметра companyId (null — все компании). */
    private static final String SCOPE = "(cast(? as bigint) is null or company_id = ?)";

    private int count(String sql, Long companyId) {
        return count(sql, (Object) companyId, companyId);
    }

    private int count(String sql, Object... args) {
        Integer n = jdbc.queryForObject(sql, Integer.class, args);
        return n == null ? 0 : n;
    }
}
