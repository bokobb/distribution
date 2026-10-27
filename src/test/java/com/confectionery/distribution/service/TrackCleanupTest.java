package com.confectionery.distribution.service;

import com.confectionery.distribution.TestData;
import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.TestcontainersConfiguration;
import com.confectionery.distribution.domain.AppEventKind;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/** Ночная очистка: точки GPS старше 6 месяцев и журнал старше года удаляются, свежие остаются. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class TrackCleanupTest {

    @Autowired
    TestData data;
    @Autowired
    TrackCleanup cleanup;
    @Autowired
    JdbcTemplate jdbc;

    @Test
    void старыеТочкиИЖурналУдаляются() {
        World w = data.world("Очистка");
        LocalDateTime now = data.today().atTime(12, 0);
        data.point(w.agent(), now.minusMonths(7), 42.3, 69.5);
        data.point(w.agent(), now.minusMonths(5), 42.3, 69.5);
        data.event(w.agent(), now.minusMonths(13), AppEventKind.LOGIN);
        data.event(w.agent(), now.minusMonths(7), AppEventKind.DAY_START);

        cleanup.run();

        assertThat(jdbc.queryForList("select recorded_at from gps_points where user_id = ?", LocalDateTime.class, w.agent().getId()))
                .containsExactly(now.minusMonths(5));
        assertThat(jdbc.queryForList("select kind from app_events where user_id = ?", String.class, w.agent().getId()))
                .containsExactly("DAY_START");
    }
}
