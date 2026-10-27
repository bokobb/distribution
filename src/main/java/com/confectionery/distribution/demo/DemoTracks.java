package com.confectionery.distribution.demo;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.AppEventRepository;
import com.confectionery.distribution.repository.DeliveryRepository;
import com.confectionery.distribution.repository.GpsPointRepository;
import com.confectionery.distribution.repository.VisitRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

/**
 * Профиль demo: треки GPS и журнал приложения за дни, когда у торговых и экспедиторов есть визиты или
 * выдачи. Телефон выезжает за полчаса до первой отметки, едет от точки к точке (по прямой, с небольшим
 * разбросом), после последней возвращается; точка раз в 5 минут. У части людей днём на полчаса
 * выключается GPS. Что телефон ещё не отправил (последняя синхронизация раньше) — не попадает.
 */
@Component
@Profile("demo")
@RequiredArgsConstructor
class DemoTracks {

    private static final int STEP_MIN = 5;
    private static final String[] PHONES = {"Samsung Galaxy A15", "Redmi Note 12", "Samsung Galaxy A25", "Tecno Spark 10", "Redmi 13C"};

    private final VisitRepository visits;
    private final DeliveryRepository deliveries;
    private final GpsPointRepository gps;
    private final AppEventRepository events;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    private record Key(Employee who, LocalDate date) {
    }

    /** Отметка дня: приехал at, уехал leave, в точке lat/lng. */
    private record Stop(LocalDateTime at, LocalDateTime leave, double lat, double lng) {
    }

    /** Сколько дней людей заполнено. */
    int fill() {
        Set<String> done = new HashSet<>(jdbc.queryForList(
                "select distinct user_id || ':' || cast(event_at as date) from app_events", String.class));
        Map<Key, List<Stop>> days = new LinkedHashMap<>();
        for (Visit v : visits.findAll()) {
            double[] at = place(v.getLat(), v.getLng(), v.getOutlet());
            if (at == null) continue;
            LocalDateTime leave = v.getFinishedAt() == null ? v.getStartedAt().plusMinutes(8) : v.getFinishedAt();
            days.computeIfAbsent(new Key(v.getAgent(), v.getStartedAt().toLocalDate()), k -> new ArrayList<>())
                    .add(new Stop(v.getStartedAt(), leave, at[0], at[1]));
        }
        for (Delivery d : deliveries.findAll()) {
            double[] at = place(d.getLat(), d.getLng(), d.getOrder().getOutlet());
            if (at == null || d.getExpeditor() == null) continue;
            days.computeIfAbsent(new Key(d.getExpeditor(), d.getDeliveredAt().toLocalDate()), k -> new ArrayList<>())
                    .add(new Stop(d.getDeliveredAt(), d.getDeliveredAt().plusMinutes(10), at[0], at[1]));
        }
        Map<Long, LocalDate> firstDay = new HashMap<>();
        days.keySet().forEach(k -> firstDay.merge(k.who().getId(), k.date(), (a, b) -> a.isBefore(b) ? a : b));
        int n = 0;
        for (Map.Entry<Key, List<Stop>> e : days.entrySet()) {
            Key k = e.getKey();
            if (done.contains(k.who().getId() + ":" + k.date())) continue;
            day(k.who(), k.date(), e.getValue(), k.date().equals(firstDay.get(k.who().getId())));
            n++;
        }
        return n;
    }

    private void day(Employee who, LocalDate date, List<Stop> stops, boolean login) {
        stops.sort(Comparator.comparing(Stop::at));
        Random rnd = new Random(who.getId() * 100_003 + date.toEpochDay());
        LocalDateTime now = LocalDateTime.now(clock);
        // что телефон не успел отправить, сервер ещё не видел
        LocalDateTime sent = who.getLastSync() != null && who.getLastSync().isBefore(now) ? who.getLastSync() : now;
        Stop first = stops.get(0), last = stops.get(stops.size() - 1);
        double[] base = DemoGeo.near(first.lat(), first.lng(), 900 + rnd.nextInt(600), rnd.nextLong());
        LocalDateTime start = first.at().minusMinutes(25 + rnd.nextInt(15)), end = last.leave().plusMinutes(20 + rnd.nextInt(20));

        List<Stop> way = new ArrayList<>();
        way.add(new Stop(start, start, base[0], base[1]));
        way.addAll(stops);
        way.add(new Stop(end, end, base[0], base[1]));

        String device = PHONES[(int) (who.getId() % PHONES.length)];
        String version = who.getId() % 4 == 3 ? "0.9.8" : "1.0.0";
        List<AppEvent> log = new ArrayList<>();
        if (login) log.add(event(who, start.minusMinutes(7), AppEventKind.LOGIN, device, version, null));
        log.add(event(who, start.minusMinutes(5), AppEventKind.APP_OPEN, device, version, null));
        log.add(event(who, start, AppEventKind.DAY_START, device, version, null));
        // у каждого третьего днём на полчаса выключен GPS
        LocalDateTime off = who.getId() % 3 == 1 ? date.atTime(13, 5 + rnd.nextInt(20)) : null;
        LocalDateTime on = off == null ? null : off.plusMinutes(30 + rnd.nextInt(15));
        if (off != null && off.isAfter(start) && on.isBefore(end)) {
            log.add(event(who, off, AppEventKind.GPS_OFF, device, version, null));
            log.add(event(who, on, AppEventKind.GPS_ON, device, version, null));
        } else off = on = null;
        for (LocalDateTime t = start.plusMinutes(60); t.isBefore(end); t = t.plusMinutes(60 + rnd.nextInt(30)))
            log.add(event(who, t, AppEventKind.SYNC, device, version, null));
        log.add(event(who, end, AppEventKind.DAY_END, device, version, null));
        events.saveAll(log.stream().filter(ev -> !ev.getEventAt().isAfter(sent)).toList());

        List<GpsPoint> points = new ArrayList<>();
        int battery = 90 + rnd.nextInt(10);
        for (LocalDateTime t = start; !t.isAfter(end) && !t.isAfter(sent); t = t.plusMinutes(STEP_MIN).plusSeconds(rnd.nextInt(20))) {
            if (off != null && t.isAfter(off) && t.isBefore(on)) continue;
            double[] at = at(way, t);
            double[] p = DemoGeo.near(at[0], at[1], rnd.nextInt(20), rnd.nextLong());
            GpsPoint g = new GpsPoint().setUser(who).setRecordedAt(t.withNano(0)).setLat(p[0]).setLng(p[1])
                    .setAccuracy(5 + rnd.nextInt(20)).setBattery(Math.max(5, battery - (int) Duration.between(start, t).toMinutes() / 12))
                    .setReceivedAt(t.plusMinutes(rnd.nextInt(30)));
            g.setCompany(who.getCompany());
            points.add(g);
        }
        gps.saveAll(points);
    }

    private static AppEvent event(Employee who, LocalDateTime at, AppEventKind kind, String device, String version, String note) {
        AppEvent e = new AppEvent().setUser(who).setEventAt(at.withNano(0)).setKind(kind).setDevice(device).setAppVersion(version)
                .setNote(note).setReceivedAt(at.withNano(0));
        e.setCompany(who.getCompany());
        return e;
    }

    /** Где телефон в момент t: стоит у точки или едет по прямой к следующей. */
    private static double[] at(List<Stop> way, LocalDateTime t) {
        for (int i = 0; i < way.size(); i++) {
            Stop s = way.get(i);
            if (!t.isAfter(s.leave())) {
                if (i == 0 || !t.isBefore(s.at())) return new double[]{s.lat(), s.lng()};
                Stop prev = way.get(i - 1);
                double total = Duration.between(prev.leave(), s.at()).toSeconds(), done = Duration.between(prev.leave(), t).toSeconds();
                double f = total <= 0 ? 1 : done / total;
                return new double[]{prev.lat() + (s.lat() - prev.lat()) * f, prev.lng() + (s.lng() - prev.lng()) * f};
            }
        }
        Stop end = way.get(way.size() - 1);
        return new double[]{end.lat(), end.lng()};
    }

    private static double[] place(Double lat, Double lng, Outlet o) {
        if (lat != null && lng != null) return new double[]{lat, lng};
        if (o.getLat() != null && o.getLng() != null) return new double[]{o.getLat(), o.getLng()};
        return null;
    }
}
