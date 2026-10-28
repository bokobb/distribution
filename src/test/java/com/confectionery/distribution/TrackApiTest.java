package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Журнал и GPS с телефона: только рабочий день, повтор пачки без дублей, последняя связь телефона. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class TrackApiTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private ResultActions send(String jwt, String json) throws Exception {
        return mvc.perform(post("/api/mobile/track").header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    @Test
    void рабочийДеньИТочки_повторБезДублей() throws Exception {
        World w = data.world("Трек");
        String jwt = data.jwt(w.expeditor());
        LocalDateTime start = LocalDateTime.now().truncatedTo(ChronoUnit.MINUTES).minusHours(1);
        String batch = """
                {"events": [{"uuid": "6f1c2a52-8d55-4c1e-9d5a-0a8a2c1b0001", "at": "%s", "kind": "DAY_START",
                             "appVersion": "1.0.0+1", "device": "Samsung SM-A515F"}],
                 "points": [{"at": "%s", "lat": 42.31, "lng": 69.59, "accuracy": 12, "battery": 80},
                            {"at": "%s", "lat": 42.32, "lng": 69.60, "accuracy": 15, "battery": 79}],
                 "unsent": 3}""".formatted(start, start.minusMinutes(5), start.plusMinutes(5));

        send(jwt, batch).andExpect(status().isOk())
                .andExpect(jsonPath("$.events").value(1))
                .andExpect(jsonPath("$.points").value(1))
                .andExpect(jsonPath("$.outsideDay").value(1));
        send(jwt, batch).andExpect(jsonPath("$.events").value(0)).andExpect(jsonPath("$.points").value(0))
                .andExpect(jsonPath("$.duplicates").value(2));

        assertThat(jdbc.queryForObject("select count(*) from gps_points where user_id = ?", Integer.class, w.expeditor().getId())).isEqualTo(1);
        assertThat(jdbc.queryForObject("select unsent from users where id = ?", Integer.class, w.expeditor().getId())).isEqualTo(3);
        assertThat(jdbc.queryForObject("select last_sync from users where id = ?", LocalDateTime.class, w.expeditor().getId())).isNotNull();
    }

    @Test
    void безВходаНеПринимается() throws Exception {
        mvc.perform(post("/api/mobile/track").contentType(MediaType.APPLICATION_JSON).content("{\"events\": [], \"points\": []}"))
                .andExpect(status().isUnauthorized());
    }
}
