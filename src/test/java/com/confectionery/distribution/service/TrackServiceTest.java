package com.confectionery.distribution.service;

import com.confectionery.distribution.TestData;
import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.TestcontainersConfiguration;
import com.confectionery.distribution.domain.AppEventKind;
import com.confectionery.distribution.service.TrackService.Accepted;
import com.confectionery.distribution.service.TrackService.Batch;
import com.confectionery.distribution.service.TrackService.EventIn;
import com.confectionery.distribution.service.TrackService.PointIn;
import com.confectionery.distribution.tenant.TenantContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Приём GPS и журнала с телефона: только рабочий день, без дублей, неверное не сохраняется, только своя компания. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class TrackServiceTest {

    @Autowired
    TestData data;
    @Autowired
    TrackService track;
    @Autowired
    JdbcTemplate jdbc;

    World w;
    LocalDateTime day;

    @BeforeEach
    void setUp() {
        w = data.world("GPS");
        day = data.today().minusDays(1).atStartOfDay();
    }

    private Accepted send(Long userId, List<EventIn> events, List<PointIn> points) {
        return TenantContext.call(w.id(), () -> track.accept(userId, new Batch(events, points)));
    }

    private static EventIn ev(LocalDateTime at, String kind) {
        return new EventIn(UUID.randomUUID(), at, kind, "1.0.0", "Samsung A15", null);
    }

    private static PointIn pt(LocalDateTime at) {
        return new PointIn(at, 42.3, 69.59, 12, 80);
    }

    private List<LocalDateTime> saved() {
        return jdbc.queryForList("select recorded_at from gps_points where user_id = ? order by recorded_at", LocalDateTime.class, w.agent().getId());
    }

    @Test
    void точкиТолькоВРабочийДень() {
        // день открыт и закрыт одной пачкой, точки — следующей
        Accepted first = send(w.agent().getId(), List.of(ev(day.plusHours(9), "DAY_START"), ev(day.plusHours(18), "DAY_END")), List.of());
        assertThat(first.events()).isEqualTo(2);

        Accepted r = send(w.agent().getId(), List.of(), List.of(pt(day.plusHours(8).plusMinutes(50)), pt(day.plusHours(9).plusMinutes(5)),
                pt(day.plusHours(17).plusMinutes(55)), pt(day.plusHours(18).plusMinutes(10))));
        assertThat(r.points()).isEqualTo(2);
        assertThat(r.outsideDay()).isEqualTo(2);
        assertThat(saved()).containsExactly(day.plusHours(9).plusMinutes(5), day.plusHours(17).plusMinutes(55));
    }

    @Test
    void деньНеЗакрыт_точкиДоКонцаДаты() {
        Accepted r = send(w.agent().getId(), List.of(ev(day.plusHours(9), "DAY_START")),
                List.of(pt(day.plusHours(23).plusMinutes(50)), pt(day.plusDays(1).plusMinutes(10))));
        assertThat(r.points()).isEqualTo(1);
        assertThat(r.outsideDay()).isEqualTo(1);
        assertThat(saved()).containsExactly(day.plusHours(23).plusMinutes(50));
    }

    @Test
    void повторнаяПачкаНеСоздаётДублей() {
        List<EventIn> events = List.of(ev(day.plusHours(9), "DAY_START"), ev(day.plusHours(9), "APP_OPEN"));
        List<PointIn> points = List.of(pt(day.plusHours(9).plusMinutes(5)), pt(day.plusHours(9).plusMinutes(10)));
        send(w.agent().getId(), events, points);
        Accepted again = send(w.agent().getId(), events, points);
        assertThat(again.events()).isZero();
        assertThat(again.points()).isZero();
        assertThat(again.duplicates()).isEqualTo(4);
        assertThat(saved()).hasSize(2);
        assertThat(jdbc.queryForObject("select count(*) from app_events where user_id = ?", Integer.class, w.agent().getId())).isEqualTo(2);
    }

    @Test
    void неверныеЗаписиНеСохраняются() {
        LocalDateTime future = LocalDateTime.now().plusHours(1);
        Accepted r = send(w.agent().getId(),
                List.of(ev(day.plusHours(9), "DAY_START"), ev(day.plusHours(10), "CRASH"), ev(future, "SYNC"),
                        new EventIn(null, day.plusHours(11), "SYNC", null, null, null)),
                List.of(new PointIn(day.plusHours(10), 95.0, 69.5, null, null), new PointIn(day.plusHours(10), 0.0, 0.0, null, null),
                        new PointIn(day.plusHours(11), 42.3, 69.5, -5, 140)));
        assertThat(r.events()).isEqualTo(1);
        assertThat(r.points()).isEqualTo(1);
        assertThat(r.invalid()).isEqualTo(5);
        assertThat(jdbc.queryForMap("select accuracy_m, battery from gps_points where user_id = ?", w.agent().getId()))
                .containsEntry("accuracy_m", null).containsEntry("battery", null);
    }

    @Test
    void толькоТорговыеИЭкспедиторыСвоейКомпании() {
        assertThatThrownBy(() -> send(w.operator().getId(), List.of(), List.of())).isInstanceOf(FormException.class);
        World other = data.world("Чужой GPS");
        assertThatThrownBy(() -> send(other.agent().getId(), List.of(ev(day.plusHours(9), "DAY_START")), List.of()))
                .isInstanceOf(NotFoundException.class);
        assertThat(jdbc.queryForObject("select count(*) from app_events where user_id = ?", Integer.class, other.agent().getId())).isZero();
    }

    @Test
    void рабочиеПромежутки() {
        List<TrackService.Mark> marks = List.of(
                new TrackService.Mark(day.plusHours(13), AppEventKind.DAY_START),
                new TrackService.Mark(day.plusHours(8), AppEventKind.DAY_END),
                new TrackService.Mark(day.plusHours(9), AppEventKind.DAY_START),
                new TrackService.Mark(day.plusHours(10), AppEventKind.DAY_START),
                new TrackService.Mark(day.plusHours(12), AppEventKind.DAY_END));
        assertThat(TrackService.workSpans(marks, day.toLocalDate())).containsExactly(
                new TrackService.Span(day.plusHours(9), day.plusHours(12), true),
                new TrackService.Span(day.plusHours(13), day.toLocalDate().atTime(23, 59, 59), false));
    }
}
