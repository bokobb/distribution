package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.AppEventKind;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.repository.EmployeeRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

/**
 * Приём GPS и журнала с телефона торгового или экспедитора. Телефон копит записи без сети и шлёт пачкой;
 * пачку можно прислать повторно — дублей не будет. Точка сохраняется, только если снята в рабочий день:
 * между «Начал день» и «Закончил день» (не закрыл — до конца той же даты). Адрес — POST /api/mobile/track.
 */
@Service
@RequiredArgsConstructor
public class TrackService {

    /** Время на телефоне может спешить — дальше этого запаса в будущее запись не принимается. */
    private static final int CLOCK_SKEW_MIN = 10;

    private final EmployeeRepository employees;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** Точка с телефона: время снятия, координаты, точность (м) и заряд (%) — если телефон их знает. */
    public record PointIn(LocalDateTime at, Double lat, Double lng, Integer accuracy, Integer battery) {
    }

    /** Запись журнала с телефона; uuid создаёт телефон, kind — имя из AppEventKind. */
    public record EventIn(UUID uuid, LocalDateTime at, String kind, String appVersion, String device, String note) {
    }

    public record Batch(List<EventIn> events, List<PointIn> points) {
    }

    /** Итог приёма: сохранено записей журнала и точек, уже были, точки вне рабочего дня, не приняты как неверные. */
    public record Accepted(int events, int points, int duplicates, int outsideDay, int invalid) {
    }

    @Transactional
    public Accepted accept(Long userId, Batch batch) {
        Employee e = employees.findById(userId).orElseThrow(NotFoundException::new);
        if (e.getRole() != Role.AGENT && e.getRole() != Role.EXPEDITOR)
            throw new FormException("GPS и журнал приложения — только у торговых и экспедиторов");
        LocalDateTime now = LocalDateTime.now(clock), latest = now.plusMinutes(CLOCK_SKEW_MIN);
        int invalid = 0, duplicates = 0, outside = 0;

        List<Object[]> events = new ArrayList<>();
        for (EventIn ev : batch.events() == null ? List.<EventIn>of() : batch.events()) {
            AppEventKind kind = kind(ev.kind());
            if (ev.uuid() == null || ev.at() == null || ev.at().isAfter(latest) || kind == null) {
                invalid++;
                continue;
            }
            events.add(new Object[]{e.getCompanyId(), ev.uuid(), e.getId(), ev.at(), kind.name(),
                    cut(ev.appVersion(), 32), cut(ev.device(), 100), cut(ev.note(), 300), now});
        }
        int savedEvents = saved(jdbc.batchUpdate("insert into app_events (company_id, uuid, user_id, event_at, kind, app_version, device, note, received_at) "
                + "values (?, ?, ?, ?, ?, ?, ?, ?, ?) on conflict (uuid) do nothing", events));
        duplicates += events.size() - savedEvents;

        List<PointIn> valid = new ArrayList<>();
        for (PointIn p : batch.points() == null ? List.<PointIn>of() : batch.points()) {
            if (p.at() == null || p.at().isAfter(latest) || p.lat() == null || p.lng() == null || Math.abs(p.lat()) > 90
                    || Math.abs(p.lng()) > 180 || p.lat() == 0 && p.lng() == 0) invalid++;
            else valid.add(p);
        }
        Map<LocalDate, List<Span>> spans = new HashMap<>();
        List<Object[]> points = new ArrayList<>();
        for (PointIn p : valid) {
            List<Span> day = spans.computeIfAbsent(p.at().toLocalDate(), d -> workSpans(dayMarks(e.getId(), d), d));
            if (day.stream().noneMatch(s -> s.contains(p.at()))) {
                outside++;
                continue;
            }
            Integer accuracy = p.accuracy() == null || p.accuracy() < 0 ? null : p.accuracy();
            Integer battery = p.battery() == null || p.battery() < 0 || p.battery() > 100 ? null : p.battery();
            points.add(new Object[]{e.getCompanyId(), e.getId(), p.at(), p.lat(), p.lng(), accuracy, battery, now});
        }
        int savedPoints = saved(jdbc.batchUpdate("insert into gps_points (company_id, user_id, recorded_at, lat, lng, accuracy_m, battery, received_at) "
                + "values (?, ?, ?, ?, ?, ?, ?, ?) on conflict (user_id, recorded_at) do nothing", points));
        duplicates += points.size() - savedPoints;
        return new Accepted(savedEvents, savedPoints, duplicates, outside, invalid);
    }

    /** Отметка начала или конца рабочего дня. */
    public record Mark(LocalDateTime at, AppEventKind kind) {
    }

    /** Рабочий промежуток; не закрыт (closed = false) — до конца даты. */
    public record Span(LocalDateTime from, LocalDateTime to, boolean closed) {
        public boolean contains(LocalDateTime t) {
            return !t.isBefore(from) && !t.isAfter(to);
        }
    }

    /**
     * Рабочие промежутки за день по отметкам: «Начал день» открывает, «Закончил день» закрывает; второе
     * «Начал» при открытом дне и «Закончил» без начала не считаются. Не закрыт — до конца даты.
     */
    public static List<Span> workSpans(List<Mark> marks, LocalDate date) {
        List<Mark> sorted = new ArrayList<>(marks);
        sorted.sort(Comparator.comparing(Mark::at));
        List<Span> out = new ArrayList<>();
        LocalDateTime open = null;
        for (Mark m : sorted) {
            if (!m.at().toLocalDate().equals(date)) continue;
            if (m.kind() == AppEventKind.DAY_START && open == null) open = m.at();
            else if (m.kind() == AppEventKind.DAY_END && open != null) {
                out.add(new Span(open, m.at(), true));
                open = null;
            }
        }
        if (open != null) out.add(new Span(open, date.atTime(23, 59, 59), false));
        return out;
    }

    private List<Mark> dayMarks(Long userId, LocalDate date) {
        return jdbc.query("select event_at, kind from app_events where user_id = ? and kind in ('DAY_START', 'DAY_END') "
                        + "and event_at >= ? and event_at < ?",
                (rs, i) -> new Mark(rs.getObject(1, LocalDateTime.class), AppEventKind.valueOf(rs.getString(2))),
                userId, date.atStartOfDay(), date.plusDays(1).atStartOfDay());
    }

    private static AppEventKind kind(String name) {
        if (name == null) return null;
        try {
            return AppEventKind.valueOf(name);
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private static String cut(String s, int max) {
        if (s == null || s.isBlank()) return null;
        s = s.strip();
        return s.length() > max ? s.substring(0, max) : s;
    }

    private static int saved(int[] counts) {
        int n = 0;
        for (int c : counts) if (c > 0) n += c;
        return n;
    }
}
