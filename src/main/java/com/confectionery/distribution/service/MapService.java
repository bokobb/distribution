package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.AppEventRepository;
import com.confectionery.distribution.repository.DeliveryRepository;
import com.confectionery.distribution.repository.GpsPointRepository;
import com.confectionery.distribution.repository.OutletRepository;
import com.confectionery.distribution.repository.RouteRepository;
import com.confectionery.distribution.repository.VisitRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Карта дня: магазины (цветом их торгового) и пути людей. Путь — трек GPS телефона за рабочий день; поверх
 * него визиты торгового и выдачи экспедитора по времени. Точка визита — где был телефон при отметке, без
 * неё — сам магазин. Нет GPS — путь рисуется по визитам и выдачам.
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
    private final GpsPointRepository gps;
    private final AppEventRepository events;

    /** Точка пути: kind — ORDER, NO_ORDER (визит), DELIVERED, PARTIAL, REFUSED (выдача). */
    public record Stop(double lat, double lng, String time, String outlet, String kind, String note) {
    }

    /**
     * Человек на карте; track — куски трека GPS (между ними сигнала не было дольше 15 минут), точка —
     * [широта, долгота]; km — длина трека; summary — строка под именем в списке.
     */
    public record Person(Long id, String name, String role, String color, List<Stop> stops, List<List<double[]>> track,
                         double km, String summary) {
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

        Map<Long, GpsTrack> tracks = new HashMap<>();
        gps.findByRecordedAtGreaterThanEqualAndRecordedAtLessThanOrderByRecordedAtAsc(from, to).stream()
                .collect(Collectors.groupingBy(p -> p.getUser().getId()))
                .forEach((id, list) -> tracks.put(id, GpsTrack.of(list)));
        Map<Long, List<TrackService.Mark>> marks = new HashMap<>();
        for (AppEvent ev : events.findByEventAtGreaterThanEqualAndEventAtLessThanOrderByEventAtAsc(from, to))
            if (ev.getKind() == AppEventKind.DAY_START || ev.getKind() == AppEventKind.DAY_END)
                marks.computeIfAbsent(ev.getUser().getId(), k -> new ArrayList<>()).add(new TrackService.Mark(ev.getEventAt(), ev.getKind()));

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
        List<double[]> trackPoints = new ArrayList<>();
        for (Who w : who) {
            List<Stop> list = stops.getOrDefault(w.id(), List.of());
            GpsTrack track = tracks.get(w.id());
            boolean gpsOn = track != null && !track.isEmpty();
            boolean chosen = only.contains(w.id());
            // выбраны люди — только они; иначе все, у кого за день есть отметки или трек
            if (only.isEmpty() ? list.isEmpty() && !gpsOn : !chosen) continue;
            int[] c = counts.getOrDefault(w.id(), new int[2]);
            List<TrackService.Span> work = TrackService.workSpans(marks.getOrDefault(w.id(), List.of()), date);
            LocalDateTime[] t = span.get(w.id());
            String when = !work.isEmpty() ? " · день " + workDay(work) : t == null ? "" : " · " + t[0].format(TIME) + "–" + t[1].format(TIME);
            String km = gpsOn ? " · " + km(track.km()) : "";
            String summary = list.isEmpty() && !gpsOn ? "за день отметок нет"
                    : w.role() == Role.AGENT
                    ? (c[0] == 0 ? "визитов нет" : "визитов " + c[0] + (plan.containsKey(w.id()) ? " из " + plan.get(w.id()) : "") + " · с заказом " + c[1]) + when + km
                    : (c[0] == 0 ? "выдач нет" : "выдач " + c[0] + (c[1] > 0 ? " · отказов " + c[1] : "")) + when + km;
            List<List<double[]>> path = !gpsOn ? List.of() : track.segments().stream()
                    .map(seg -> seg.stream().map(a -> new double[]{a.lat(), a.lng()}).toList()).toList();
            path.forEach(trackPoints::addAll);
            people.add(new Person(w.id(), w.name(), w.role().name(), w.color(), list, path, gpsOn ? Math.round(track.km() * 10) / 10.0 : 0, summary));
        }
        return new Day(date, center(shops, stops.values(), trackPoints), shops, people, noCoords);
    }

    /** Заказ на карте списка: цвет торгового и цвет экспедитора (серый — ещё не отгружен). */
    public record OrderPoint(Long id, String number, String outlet, String address, double lat, double lng, long sum,
                             String status, String agent, String agentColor, String expeditor, String expColor) {
    }

    /** Строка подписи цветов: кто, сколько заказов и на какую сумму. */
    public record Legend(String name, String color, int count, long sum) {
    }

    /** cut — заказов больше, чем показано; noCoords — заказов у магазинов без координат. */
    public record OrdersMap(double[] center, List<OrderPoint> points, List<Legend> agents, List<Legend> expeditors,
                            int noCoords, boolean cut) {
    }

    public static final String NOT_SHIPPED = "#8A776C";

    /** Карта списка заказов: точка — магазин заказа, цвета — как на «Карте». */
    public OrdersMap orders(Long companyId, List<Order> list, boolean cut) {
        Map<Long, String> color = new HashMap<>();
        people(companyId).forEach(w -> color.put(w.id(), w.color()));
        List<OrderPoint> points = new ArrayList<>();
        Map<String, Legend> agents = new LinkedHashMap<>(), exps = new LinkedHashMap<>();
        int noCoords = 0;
        for (Order o : list) {
            Outlet ot = o.getOutlet();
            if (ot.getLat() == null || ot.getLng() == null) {
                noCoords++;
                continue;
            }
            Employee a = o.getAgent();
            Employee e = o.getTrip() == null ? null : o.getTrip().getExpeditor();
            String aName = a == null ? "Без торгового" : a.getName();
            String aColor = a == null ? NOT_SHIPPED : color.getOrDefault(a.getId(), NOT_SHIPPED);
            String eName = e == null ? "Не отгружены" : e.getName();
            String eColor = e == null ? NOT_SHIPPED : color.getOrDefault(e.getId(), NOT_SHIPPED);
            points.add(new OrderPoint(o.getId(), o.getNumber(), ot.getName(), ot.getAddress(), ot.getLat(), ot.getLng(),
                    o.getTotal(), o.getStatus().getLabel(), aName, aColor, e == null ? null : eName, eColor));
            agents.merge(aName, new Legend(aName, aColor, 1, o.getTotal()), MapService::add);
            exps.merge(eName, new Legend(eName, eColor, 1, o.getTotal()), MapService::add);
        }
        double[] center = DEFAULT_CENTER;
        if (!points.isEmpty())
            center = new double[]{points.stream().mapToDouble(OrderPoint::lat).average().orElseThrow(),
                    points.stream().mapToDouble(OrderPoint::lng).average().orElseThrow()};
        Comparator<Legend> bySum = Comparator.comparingLong(Legend::sum).reversed();
        return new OrdersMap(center, points, agents.values().stream().sorted(bySum).toList(),
                exps.values().stream().sorted(bySum).toList(), noCoords, cut);
    }

    private static Legend add(Legend x, Legend y) {
        return new Legend(x.name(), x.color(), x.count() + y.count(), x.sum() + y.sum());
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

    /** «08:52–18:10», не закрыт — «с 08:52». */
    private static String workDay(List<TrackService.Span> work) {
        TrackService.Span last = work.get(work.size() - 1);
        String start = work.get(0).from().format(TIME);
        return last.closed() ? start + "–" + last.to().format(TIME) : "с " + start;
    }

    /** «23,4 км». */
    static String km(double km) {
        return String.format(Locale.forLanguageTag("ru"), "%.1f км", km);
    }

    private static double[] center(List<Shop> shops, Collection<List<Stop>> paths, List<double[]> track) {
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
        for (double[] p : track) {
            lat += p[0];
            lng += p[1];
            n++;
        }
        return n == 0 ? DEFAULT_CENTER : new double[]{lat / n, lng / n};
    }
}
