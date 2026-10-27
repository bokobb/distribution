package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.GpsPoint;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * Трек сотрудника за день из точек GPS. Неточные точки (хуже 100 м) и скачки быстрее 150 км/ч
 * отбрасываются. Где точек не было дольше 15 минут — разрыв: трек делится на куски, путь между ними
 * неизвестен и в километры не идёт.
 */
public record GpsTrack(List<List<At>> segments, double km) {

    public static final int GAP_MIN = 15;
    private static final int BAD_ACCURACY_M = 100;
    private static final double MAX_SPEED_KMH = 150;

    public record At(LocalDateTime at, double lat, double lng) {
    }

    /** Пропал GPS: с какого по какое время точек не было. */
    public record Gap(LocalDateTime from, LocalDateTime to) {
        public long minutes() {
            return Duration.between(from, to).toMinutes();
        }
    }

    public static GpsTrack of(List<GpsPoint> points) {
        List<GpsPoint> sorted = new ArrayList<>(points);
        sorted.sort(Comparator.comparing(GpsPoint::getRecordedAt));
        List<List<At>> segments = new ArrayList<>();
        List<At> cur = null;
        double km = 0;
        int jumps = 0;
        for (GpsPoint p : sorted) {
            if (p.getAccuracy() != null && p.getAccuracy() > BAD_ACCURACY_M) continue;
            At a = new At(p.getRecordedAt(), p.getLat(), p.getLng());
            At last = cur == null ? null : cur.get(cur.size() - 1);
            if (last != null) {
                double d = km(last, a);
                double hours = Duration.between(last.at(), a.at()).toSeconds() / 3600.0;
                boolean jump = hours > 0 && d / hours > MAX_SPEED_KMH;
                // скачок — выброс; три подряд — выбросом была прошлая точка: дальше новый кусок
                if (jump && ++jumps < 3) continue;
                if (jump || hours * 60 > GAP_MIN) last = null;
                else km += d;
            }
            jumps = 0;
            if (last == null) segments.add(cur = new ArrayList<>());
            cur.add(a);
        }
        return new GpsTrack(segments, km);
    }

    public boolean isEmpty() {
        return segments.isEmpty();
    }

    public List<At> points() {
        return segments.stream().flatMap(List::stream).toList();
    }

    /**
     * Разрывы дольше 15 минут внутри рабочих промежутков: от начала дня до первой точки, между точками и
     * от последней точки до конца дня. Незакрытый день считается до now, если он сегодня, иначе — до
     * последней точки.
     */
    public List<Gap> gaps(List<TrackService.Span> spans, LocalDateTime now) {
        List<At> all = points();
        List<Gap> out = new ArrayList<>();
        for (TrackService.Span s : spans) {
            LocalDateTime cursor = s.from();
            for (At a : all) {
                if (!s.contains(a.at())) continue;
                gap(out, cursor, a.at());
                cursor = a.at();
            }
            if (s.closed()) gap(out, cursor, s.to());
            else if (now.toLocalDate().equals(s.from().toLocalDate())) gap(out, cursor, now.isBefore(s.to()) ? now : s.to());
        }
        return out;
    }

    private static void gap(List<Gap> out, LocalDateTime from, LocalDateTime to) {
        if (Duration.between(from, to).toMinutes() > GAP_MIN) out.add(new Gap(from, to));
    }

    /** Расстояние по прямой, км (формула гаверсинусов). */
    static double km(At a, At b) {
        double r = 6371.0;
        double dLat = Math.toRadians(b.lat() - a.lat()), dLng = Math.toRadians(b.lng() - a.lng());
        double h = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(a.lat())) * Math.cos(Math.toRadians(b.lat())) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 2 * r * Math.asin(Math.sqrt(h));
    }
}
