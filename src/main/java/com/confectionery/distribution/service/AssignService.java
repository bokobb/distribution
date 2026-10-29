package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.OutletStatus;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.repository.OutletRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Закрепление магазинов за торговыми (вместо маршрутов): у магазина свой торговый, без дней и порядка обхода.
 * Страница показывает все магазины компании на карте, магазины выбранного торгового списком и торговых справа —
 * сколько за каждым магазинов и сколько из них без визита 7+ дней.
 */
@Service
@RequiredArgsConstructor
public class AssignService {

    /** Без визита столько дней и больше — магазин «давно не посещали». */
    public static final int STALE_DAYS = 7;

    private final OutletRepository outlets;
    private final EmployeeRepository employees;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** Магазин на карте и в списке. lastVisit — дата последнего визита, null — визитов не было. */
    public record Shop(Long id, String name, String address, Double lat, Double lng, Long agentId, String region,
                       LocalDate lastVisit, int orders30, boolean stale) {
    }

    /** Торговый справа: магазинов закреплено, без визита 7+ дней, район — где больше всего его магазинов. */
    public record AgentCard(Long id, String name, String initials, String region, int count, int stale) {
    }

    /** agent — выбранный торговый (null — «без торгового»). */
    public record Page(List<AgentCard> agents, int unassigned, int unassignedStale, AgentCard agent, List<Shop> shops) {
        public List<Shop> mine() {
            return shops.stream().filter(s -> Objects.equals(s.agentId(), agent == null ? null : agent.id())).toList();
        }

        public int total() {
            return shops.size();
        }

        public long onMap() {
            return shops.stream().filter(s -> s.lat() != null && s.lng() != null).count();
        }
    }

    @Transactional(readOnly = true)
    public Page page(Long companyId, Long agentId, boolean none) {
        LocalDate today = LocalDate.now(clock);
        Map<Long, LocalDate> lastVisit = new HashMap<>();
        jdbc.query("select outlet_id, max(started_at) from visits where company_id = ? group by outlet_id",
                rs -> {
                    lastVisit.put(rs.getLong(1), rs.getTimestamp(2).toLocalDateTime().toLocalDate());
                }, companyId);
        Map<Long, Integer> orders30 = new HashMap<>();
        jdbc.query("""
                select outlet_id, count(*) from orders
                where company_id = ? and created_at >= ? and status <> 'CANCELLED' group by outlet_id""",
                rs -> {
                    orders30.put(rs.getLong(1), rs.getInt(2));
                }, companyId, today.minusDays(30).atStartOfDay());

        List<Shop> shops = new ArrayList<>();
        for (Outlet o : outlets.findAllByOrderByNameAsc()) {
            if (!companyId.equals(o.getCompanyId()) || o.getStatus() == OutletStatus.CLOSED) continue;
            LocalDate lv = lastVisit.get(o.getId());
            boolean stale = lv == null || ChronoUnit.DAYS.between(lv, today) >= STALE_DAYS;
            shops.add(new Shop(o.getId(), o.getName(), o.getAddress() != null ? o.getAddress() : o.getLandmark(), o.getLat(), o.getLng(),
                    o.getAgent() == null ? null : o.getAgent().getId(), o.getRegion() == null ? null : o.getRegion().getName(),
                    lv, orders30.getOrDefault(o.getId(), 0), stale));
        }

        Map<Long, List<Shop>> byAgent = shops.stream().filter(s -> s.agentId() != null).collect(Collectors.groupingBy(Shop::agentId));
        List<AgentCard> cards = employees.findByRoleOrderByNameAsc(Role.AGENT).stream()
                .filter(e -> e.isActive() && companyId.equals(e.getCompanyId()))
                .map(e -> card(e, byAgent.getOrDefault(e.getId(), List.of())))
                .sorted(Comparator.comparingInt(AgentCard::count).reversed().thenComparing(AgentCard::name))
                .toList();
        List<Shop> free = shops.stream().filter(s -> s.agentId() == null).toList();
        AgentCard chosen = none ? null : cards.stream().filter(c -> c.id().equals(agentId)).findFirst()
                .orElse(cards.isEmpty() ? null : cards.get(0));
        return new Page(cards, free.size(), (int) free.stream().filter(Shop::stale).count(), chosen, shops);
    }

    private static AgentCard card(Employee e, List<Shop> mine) {
        String region = mine.stream().map(Shop::region).filter(Objects::nonNull)
                .collect(Collectors.groupingBy(Function.identity(), Collectors.counting()))
                .entrySet().stream().max(Map.Entry.comparingByValue()).map(Map.Entry::getKey).orElse(null);
        return new AgentCard(e.getId(), e.getName(), e.getInitials(), region, mine.size(), (int) mine.stream().filter(Shop::stale).count());
    }
}
