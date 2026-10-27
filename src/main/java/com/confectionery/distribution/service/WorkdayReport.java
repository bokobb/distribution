package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Отчёт «Рабочий день»: по каждому торговому и экспедитору за каждый день — когда начал и закончил день в
 * приложении, сколько часов, километры по GPS, визиты или выдачи, когда GPS пропадал дольше 15 минут и
 * почему; версия приложения и телефон. Ниже — журнал приложения за те же дни.
 */
@Service
@RequiredArgsConstructor
public class WorkdayReport {

    /** Больше строк журнала страница не показывает — сузьте период или людей. */
    public static final int JOURNAL_LIMIT = 500;
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("HH:mm");

    private final MapService maps;
    private final GpsPointRepository gps;
    private final AppEventRepository events;
    private final VisitRepository visits;
    private final DeliveryRepository deliveries;
    private final RouteRepository routes;
    private final Clock clock;

    /** GPS пропадал: с, по, минут, почему. */
    public record Gap(String from, String to, long minutes, String cause) {
    }

    /**
     * Человек за день. start — первое «Начал день» (null — день в приложении не начат); end — последнее
     * «Закончил день», null при open — не закрыл; minutes — рабочих минут (null — не начат).
     */
    public record Row(LocalDate date, Long id, String name, Role role, String color, LocalDateTime start, LocalDateTime end,
                      boolean open, Long minutes, boolean gpsOn, double km, String work, List<Gap> gaps, String app, boolean oldApp) {

        public long gapMinutes() {
            return gaps.stream().mapToLong(Gap::minutes).sum();
        }

        /** «8 ч 05 мин». */
        public String hours() {
            return minutes == null ? null : minutes / 60 + " ч " + String.format("%02d", minutes % 60) + " мин";
        }

        public String kmText() {
            return gpsOn ? MapService.km(km) : null;
        }
    }

    /** Строка журнала приложения. */
    public record Entry(LocalDateTime at, String name, Role role, AppEventKind kind, String version, String device, String note) {
    }

    /** cut — строк журнала больше, чем показано (последние JOURNAL_LIMIT). */
    public record Report(List<Row> rows, List<Entry> journal, boolean cut, String latestApp) {
    }

    public Report build(Long companyId, LocalDate from, LocalDate to, Collection<Long> selected) {
        Set<Long> only = selected == null ? Set.of() : new HashSet<>(selected);
        Map<Long, MapService.Who> who = new LinkedHashMap<>();
        maps.people(companyId).stream().filter(w -> only.isEmpty() || only.contains(w.id())).forEach(w -> who.put(w.id(), w));
        LocalDateTime a = from.atStartOfDay(), b = to.plusDays(1).atStartOfDay();
        LocalDateTime now = LocalDateTime.now(clock);

        Map<Key, List<GpsPoint>> points = gps.findByRecordedAtGreaterThanEqualAndRecordedAtLessThanOrderByRecordedAtAsc(a, b).stream()
                .filter(p -> who.containsKey(p.getUser().getId()))
                .collect(Collectors.groupingBy(p -> new Key(p.getUser().getId(), p.getRecordedAt().toLocalDate())));
        List<AppEvent> evs = events.findByEventAtGreaterThanEqualAndEventAtLessThanOrderByEventAtAsc(a, b).stream()
                .filter(e -> who.containsKey(e.getUser().getId())).toList();
        Map<Key, List<AppEvent>> evsOf = evs.stream().collect(Collectors.groupingBy(e -> new Key(e.getUser().getId(), e.getEventAt().toLocalDate())));
        // визиты: [всего, с заказом]; выдачи: [всего, отказов]; и время последней отметки
        Map<Key, int[]> counts = new HashMap<>();
        Map<Key, LocalDateTime> lastMark = new HashMap<>();
        for (Visit v : visits.findByStartedAtGreaterThanEqualAndStartedAtLessThan(a, b)) {
            Key k = new Key(v.getAgent().getId(), v.getStartedAt().toLocalDate());
            if (!who.containsKey(k.user())) continue;
            int[] c = counts.computeIfAbsent(k, x -> new int[2]);
            c[0]++;
            if (v.getResult() == VisitResult.ORDER) c[1]++;
            lastMark.merge(k, v.getStartedAt(), (x, y) -> x.isAfter(y) ? x : y);
        }
        for (Delivery d : deliveries.findByDeliveredAtGreaterThanEqualAndDeliveredAtLessThan(a, b)) {
            if (d.getExpeditor() == null) continue;
            Key k = new Key(d.getExpeditor().getId(), d.getDeliveredAt().toLocalDate());
            if (!who.containsKey(k.user())) continue;
            int[] c = counts.computeIfAbsent(k, x -> new int[2]);
            c[0]++;
            if (d.getStatus() == DeliveryStatus.REFUSED) c[1]++;
            lastMark.merge(k, d.getDeliveredAt(), (x, y) -> x.isAfter(y) ? x : y);
        }
        List<Route> active = routes.findAllByOrderByNameAsc().stream().filter(r -> r.isActive() && r.getAgent() != null).toList();
        String latest = evs.stream().map(AppEvent::getAppVersion).filter(Objects::nonNull).max(WorkdayReport::compareVersions).orElse(null);

        Set<Key> keys = new HashSet<>();
        keys.addAll(points.keySet());
        keys.addAll(evsOf.keySet());
        keys.addAll(counts.keySet());
        List<Row> rows = new ArrayList<>();
        for (Key k : keys) {
            MapService.Who w = who.get(k.user());
            List<AppEvent> day = evsOf.getOrDefault(k, List.of());
            List<TrackService.Span> spans = TrackService.workSpans(day.stream()
                    .map(e -> new TrackService.Mark(e.getEventAt(), e.getKind())).toList(), k.date());
            GpsTrack track = GpsTrack.of(points.getOrDefault(k, List.of()));

            LocalDateTime start = spans.isEmpty() ? null : spans.get(0).from();
            boolean open = !spans.isEmpty() && !spans.get(spans.size() - 1).closed();
            LocalDateTime end = spans.isEmpty() || open ? null : spans.get(spans.size() - 1).to();
            // не закрытый день: сегодня — до сейчас, раньше — до последнего, что пришло с телефона
            LocalDateTime last = latest(k.date().equals(now.toLocalDate()) ? now : null,
                    day.isEmpty() ? null : day.get(day.size() - 1).getEventAt(),
                    track.isEmpty() ? null : track.points().get(track.points().size() - 1).at(), lastMark.get(k));
            Long minutes = spans.isEmpty() ? null : spans.stream()
                    .mapToLong(s -> Duration.between(s.from(), s.closed() || last == null || last.isAfter(s.to()) ? s.to() : last).toMinutes())
                    .map(m -> Math.max(0, m)).sum();

            List<AppEvent> offs = day.stream().filter(e -> e.getKind() == AppEventKind.GPS_OFF).toList();
            List<Gap> gaps = track.gaps(spans, now).stream().map(g -> new Gap(g.from().format(TIME), g.to().format(TIME), g.minutes(),
                    offs.stream().anyMatch(e -> !e.getEventAt().isBefore(g.from().minusMinutes(1)) && !e.getEventAt().isAfter(g.to()))
                            ? "GPS выключен" : "нет точек: нет сигнала или телефон выключен")).toList();

            int[] c = counts.get(k);
            String work;
            if (w.role() == Role.AGENT) {
                int plan = active.stream().filter(r -> r.getAgent().getId().equals(w.id()) && r.visitsOn(k.date().getDayOfWeek()))
                        .mapToInt(r -> r.getStops().size()).sum();
                work = c == null ? (plan > 0 ? "визитов 0 из " + plan : "визитов нет")
                        : "визитов " + c[0] + (plan > 0 ? " из " + plan : "") + " · с заказом " + c[1];
            } else {
                work = c == null ? "выдач нет" : "выдач " + c[0] + (c[1] > 0 ? " · отказов " + c[1] : "");
            }
            AppEvent withApp = day.stream().filter(e -> e.getAppVersion() != null || e.getDevice() != null)
                    .reduce((x, y) -> y).orElse(null);
            String app = withApp == null ? null : String.join(" · ", Arrays.stream(new String[]{withApp.getAppVersion(), withApp.getDevice()})
                    .filter(Objects::nonNull).toList());
            boolean oldApp = withApp != null && withApp.getAppVersion() != null && latest != null && compareVersions(withApp.getAppVersion(), latest) < 0;

            rows.add(new Row(k.date(), w.id(), w.name(), w.role(), w.color(), start, end, open, minutes, !track.isEmpty(),
                    Math.round(track.km() * 10) / 10.0, work, gaps, app, oldApp));
        }
        List<Long> order = new ArrayList<>(who.keySet());
        rows.sort(Comparator.comparing(Row::date).reversed().thenComparing(r -> order.indexOf(r.id())));

        List<Entry> journal = new ArrayList<>();
        for (int i = evs.size() - 1; i >= 0 && journal.size() < JOURNAL_LIMIT; i--) {
            AppEvent e = evs.get(i);
            MapService.Who w = who.get(e.getUser().getId());
            journal.add(new Entry(e.getEventAt(), w.name(), w.role(), e.getKind(), e.getAppVersion(), e.getDevice(), e.getNote()));
        }
        return new Report(rows, journal, evs.size() > JOURNAL_LIMIT, latest);
    }

    private record Key(Long user, LocalDate date) {
    }

    private static LocalDateTime latest(LocalDateTime... times) {
        LocalDateTime out = null;
        for (LocalDateTime t : times) if (t != null && (out == null || t.isAfter(out))) out = t;
        return out;
    }

    /** Сравнение версий «1.0.10» и «1.0.9» по числам; что не число — как строка. */
    static int compareVersions(String x, String y) {
        String[] a = x.split("\\."), b = y.split("\\.");
        for (int i = 0; i < Math.max(a.length, b.length); i++) {
            String p = i < a.length ? a[i] : "0", q = i < b.length ? b[i] : "0";
            int c = p.matches("\\d{1,9}") && q.matches("\\d{1,9}") ? Integer.compare(Integer.parseInt(p), Integer.parseInt(q)) : p.compareTo(q);
            if (c != 0) return c;
        }
        return 0;
    }
}
