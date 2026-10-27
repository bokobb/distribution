package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.GpsPoint;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** Трек из точек: неточные и скачки отбрасываются, разрывы делят трек, пропажи GPS считаются в рабочем дне. */
class GpsTrackTest {

    static final LocalDateTime DAY = LocalDateTime.of(2026, 10, 20, 0, 0);

    static GpsPoint p(int hour, int minute, double lat, double lng, Integer accuracy) {
        return new GpsPoint().setRecordedAt(DAY.plusHours(hour).plusMinutes(minute)).setLat(lat).setLng(lng).setAccuracy(accuracy);
    }

    @Test
    void неточныеТочкиИСкачкиОтброшены() {
        GpsTrack t = GpsTrack.of(List.of(
                p(9, 0, 42.30, 69.58, 10),
                p(9, 5, 42.30, 69.59, 400),     // точность 400 м
                p(9, 10, 42.80, 69.58, 10),     // 55 км за 5 минут
                p(9, 15, 42.31, 69.58, 10)));
        assertThat(t.points()).extracting(GpsTrack.At::lat).containsExactly(42.30, 42.31);
        assertThat(t.km()).isBetween(1.0, 1.2);
    }

    @Test
    void выбросомБылаПерваяТочка() {
        List<GpsPoint> list = new ArrayList<>(List.of(p(9, 0, 43.30, 69.58, 10)));  // в 110 км от остальных
        for (int i = 1; i <= 5; i++) list.add(p(9, i * 5, 42.30 + i * 0.001, 69.58, 10));
        GpsTrack t = GpsTrack.of(list);
        assertThat(t.segments()).hasSize(2);
        assertThat(t.segments().get(1)).hasSize(3);
        assertThat(t.km()).isLessThan(1);
    }

    @Test
    void пропажиGpsВРабочемДне() {
        GpsTrack t = GpsTrack.of(List.of(p(9, 40, 42.30, 69.58, 10), p(9, 45, 42.30, 69.58, 10), p(13, 0, 42.30, 69.58, 10)));
        TrackService.Span closed = new TrackService.Span(DAY.plusHours(9), DAY.plusHours(14), true);
        assertThat(t.gaps(List.of(closed), DAY.plusDays(1))).extracting(GpsTrack.Gap::minutes).containsExactly(40L, 195L, 60L);

        // день не закрыт: сегодня — до сейчас, в прошлом — до последней точки
        TrackService.Span open = new TrackService.Span(DAY.plusHours(9), DAY.plusHours(23).plusMinutes(59), false);
        assertThat(t.gaps(List.of(open), DAY.plusHours(13).plusMinutes(30))).extracting(GpsTrack.Gap::minutes).containsExactly(40L, 195L, 30L);
        assertThat(t.gaps(List.of(open), DAY.plusDays(3))).extracting(GpsTrack.Gap::minutes).containsExactly(40L, 195L);
    }
}
