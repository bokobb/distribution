package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.DeliveryRepository;
import com.confectionery.distribution.repository.OutletRepository;
import com.confectionery.distribution.repository.RouteRepository;
import com.confectionery.distribution.repository.VisitRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * Карта дня: магазины (цветом их торгового) и пути людей — торговый по визитам, экспедитор по выдачам,
 * по времени. Точка пути — где был телефон при отметке, без неё — сам магазин. Полный трек по GPS
 * появится вместе с приложением.
 */
@Service
@RequiredArgsConstructor
public class MapService {

    /** Цвета людей: первые — из палитры админки, дальше — различимые на карте. */
    public static final List<String> COLORS = List.of("#B9203C", "#2F4867", "#2F6B3F", "#A8692B", "#6B3FA0",
            "#0E7C86", "#C2410C", "#4D7C0F", "#9D174D", "#1D4ED8", "#7A4B00", "#475569");
    /** Шымкент — если у магазинов ещё нет координат. */
    private static final double[] DEFAULT_CENTER = {42.3155, 69.5869};
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("HH:mm");

    private final StaffService staff;
    private final OutletRepository outlets;
    private final RouteRepository routes;
    private final VisitRepository visits;
    private final DeliveryRepository deliveries;

    /** Точка пути: kind — ORDER, NO_ORDER (визит), DELIVERED, PARTIAL, REFUSED (выдача). */
    public record Stop(double lat, double lng, String time, String outlet, String kind, String note) {
    }

    /** Человек на карте; summary — строка под именем в списке. */
    public record Person(Long id, String name, String role, String color, List<Stop> stops, String summary) {
    }

    public record Shop(Long id, String name, String address, double lat, double lng, String route, String color) {
    }

    /** noCoords — сколько работающих магазинов ещё без координат. */
    public record Day(LocalDate date, double[] center, List<Shop> outlets, List<Person> people, int noCoords) {
    }

    /** Кого можно выбрать в фильтре: торговые и экспедиторы, с цветом. */
    public record Who(Long id, String name, Role role, String color) {
    }

    public List<Who> people(Long companyId) {
        List<Who> out = new ArrayList<>();
        int i = 0;
        for (Role role : List.of(Role.AGENT, Role.EXPEDITOR))
            for (Employee e : staff.staff(companyId, role))
                out.add(new Who(e.getId(), e.getName(), role, COLORS.get(i++ % COLORS.size())));
        return out;
    }

    /** Карта на день; selected — id людей (пусто — все, у кого есть точки, и все магазины). */
    public Day day(Long companyId, LocalDate date, Collection<Long> selected) {
        Set<Long> only = selected == null ? Set.of() : new HashSet<>(selected);
        List<Who> who = people(companyId);
        Map<Long, Who> byId = new HashMap<>();
        who.forEach(w -> byId.put(w.id(), w));
        LocalDateTime from = date.atStartOfDay(), to = date.plusDays(1).atStartOfDay();

        Map<Long, List<Stop>> stops = new HashMap<>();
        Map<Long, int[]> counts = new HashMap<>(); // визиты: [всего, с заказом]; выдачи: [всего, отказов]
        Map<Long, LocalDateTime[]> span = new HashMap<>();
        List<Visit> vs = new ArrayList<>(visits.findByStartedAtGreaterThanEqualAndStartedAtLessThan(from, to));
        vs.sort(Comparator.comparing(Visit::getStartedAt));
        for (Visit v : vs) {
            Who w = byId.get(v.getAgent().getId());
            if (w == null || !only.isEmpty() && !only.contains(w.id())) continue;
            double[] at = at(v.getLat(), v.getLng(), v.getOutlet());
            if (at == null) continue;
            boolean order = v.getResult() == VisitResult.ORDER;
            String note = order ? "заказ" : "без заказа" + (v.getRefuseReason() == null ? "" : ": " + v.getRefuseReason());
            if (v.getDistance() != null && v.getDistance() > 0) note += " · " + v.getDistance() + " м от магазина";
            stops.computeIfAbsent(w.id(), k -> new ArrayList<>())
                    .add(new Stop(at[0], at[1], v.getStartedAt().format(TIME), v.getOutlet().getName(), v.getResult().name(), note));
            int[] c = counts.computeIfAbsent(w.id(), k -> new int[2]);
            c[0]++;
            if (order) c[1]++;
            track(span, w.id(), v.getStartedAt());
        }
        List<Delivery> ds = new ArrayList<>(deliveries.findByDeliveredAtGreaterThanEqualAndDeliveredAtLessThan(from, to));
        ds.sort(Comparator.comparing(Delivery::getDeliveredAt));
        for (Delivery d : ds) {
            if (d.getExpeditor() == null) continue;
            Who w = byId.get(d.getExpeditor().getId());
            if (w == null || !only.isEmpty() && !only.contains(w.id())) continue;
            Outlet o = d.getOrder().getOutlet();
            double[] at = at(d.getLat(), d.getLng(), o);
            if (at == null) continue;
            String note = "№ " + d.getOrder().getNumber() + " · " + switch (d.getStatus()) {
                case DELIVERED -> "выдан полностью";
                case PARTIAL -> "выдан частично";
                case REFUSED -> "отказ" + (d.getRefuseReason() == null ? "" : ": " + d.getRefuseReason());
            };
            stops.computeIfAbsent(w.id(), k -> new ArrayList<>())
                    .add(new Stop(at[0], at[1], d.getDeliveredAt().format(TIME), o.getName(), d.getStatus().name(), note));
            int[] c = counts.computeIfAbsent(w.id(), k -> new int[2]);
            c[0]++;
            if (d.getStatus() == DeliveryStatus.REFUSED) c[1]++;
            track(span, w.id(), d.getDeliveredAt());
        }

        // магазины — цветом их торгового; план визитов — по маршрутам этого дня недели
        Map<Long, Integer> plan = new HashMap<>();
        Map<Long, Who> agentOfOutlet = new HashMap<>();
        Map<Long, String> routeOfOutlet = new HashMap<>();
        for (Route r : routes.findAllByOrderByNameAsc()) {
            if (r.getAgent() == null || !r.isActive()) continue;
            Who w = byId.get(r.getAgent().getId());
            if (w == null) continue;
            if (r.visitsOn(date.getDayOfWeek())) plan.merge(w.id(), r.getStops().size(), Integer::sum);
            for (RouteOutlet ro : r.getStops()) {
                agentOfOutlet.put(ro.getOutlet().getId(), w);
                routeOfOutlet.put(ro.getOutlet().getId(), r.getName());
            }
        }
        boolean agentsChosen = only.stream().anyMatch(id -> byId.containsKey(id) && byId.get(id).role() == Role.AGENT);
        List<Shop> shops = new ArrayList<>();
        int noCoords = 0;
        for (Outlet o : outlets.findAllByOrderByNameAsc()) {
            if (companyId != null && !companyId.equals(o.getCompanyId())) continue;
            if (o.getStatus() == OutletStatus.CLOSED) continue;
            Who w = agentOfOutlet.get(o.getId());
            if (agentsChosen && (w == null || !only.contains(w.id()))) continue;
            if (o.getLat() == null || o.getLng() == null) {
                noCoords++;
                continue;
            }
            shops.add(new Shop(o.getId(), o.getName(), o.getAddress(), o.getLat(), o.getLng(),
                    routeOfOutlet.get(o.getId()), w == null ? "#8A776C" : w.color()));
        }

        List<Person> people = new ArrayList<>();
        for (Who w : who) {
            List<Stop> list = stops.getOrDefault(w.id(), List.of());
            boolean chosen = only.contains(w.id());
            if (list.isEmpty() && !chosen) continue;
            int[] c = counts.getOrDefault(w.id(), new int[2]);
            LocalDateTime[] t = span.get(w.id());
            String when = t == null ? "" : " · " + t[0].format(TIME) + "–" + t[1].format(TIME);
            String summary = list.isEmpty() ? "за день отметок нет"
                    : w.role() == Role.AGENT
                    ? "визитов " + c[0] + (plan.containsKey(w.id()) ? " из " + plan.get(w.id()) : "") + " · с заказом " + c[1] + when
                    : "выдач " + c[0] + (c[1] > 0 ? " · отказов " + c[1] : "") + when;
            people.add(new Person(w.id(), w.name(), w.role().name(), w.color(), list, summary));
        }
        return new Day(date, center(shops, stops.values()), shops, people, noCoords);
    }

    private static double[] at(Double lat, Double lng, Outlet o) {
        if (lat != null && lng != null) return new double[]{lat, lng};
        if (o.getLat() != null && o.getLng() != null) return new double[]{o.getLat(), o.getLng()};
        return null;
    }

    private static void track(Map<Long, LocalDateTime[]> span, Long id, LocalDateTime t) {
        LocalDateTime[] s = span.computeIfAbsent(id, k -> new LocalDateTime[]{t, t});
        if (t.isBefore(s[0])) s[0] = t;
        if (t.isAfter(s[1])) s[1] = t;
    }

    private static double[] center(List<Shop> shops, Collection<List<Stop>> paths) {
        double lat = 0, lng = 0;
        int n = 0;
        for (Shop s : shops) {
            lat += s.lat();
            lng += s.lng();
            n++;
        }
        for (List<Stop> p : paths)
            for (Stop s : p) {
                lat += s.lat();
                lng += s.lng();
                n++;
            }
        return n == 0 ? DEFAULT_CENTER : new double[]{lat / n, lng / n};
    }
}
