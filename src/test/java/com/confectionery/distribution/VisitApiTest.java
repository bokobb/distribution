package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Визит агента с телефона: причина без заказа, расстояние до магазина, повтор без дублей, фото полки. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class VisitApiTest {

    /** Начало JPEG — сервер проверяет только его. */
    static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 1, 2, 3};

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;
    @Value("${distribution.files.dir}")
    String filesDir;

    private ResultActions send(String jwt, String json) throws Exception {
        return mvc.perform(post("/api/mobile/agent/visits").header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private static String visit(UUID uuid, World w, LocalDateTime at, String result, String reason) {
        return """
                {"uuid": "%s", "outletId": %d, "routeId": %d, "startedAt": "%s", "finishedAt": "%s",
                 "lat": 42.3010, "lng": 69.6000, "result": "%s", "refuseReason": %s}"""
                .formatted(uuid, w.outlet().getId(), w.route().getId(), at, at.plusMinutes(7), result,
                        reason == null ? "null" : '"' + reason + '"');
    }

    @Test
    void безЗаказа_причинаОбязательна_расстояние_повторБезДубля() throws Exception {
        World w = data.world("Визит");
        data.place(w.outlet(), 42.3000, 69.6000);
        String jwt = data.jwt(w.agent());
        UUID uuid = UUID.randomUUID();
        LocalDateTime at = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(30);

        send(jwt, visit(uuid, w, at, "NO_ORDER", null)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Укажите, почему без заказа"));
        send(jwt, visit(uuid, w, at, "NO_ORDER", "Товар ещё есть")).andExpect(status().isOk())
                .andExpect(jsonPath("$.distance").value(111))
                .andExpect(jsonPath("$.refuseReason").value("Товар ещё есть"))
                .andExpect(jsonPath("$.photo").value(false));
        send(jwt, visit(uuid, w, at, "NO_ORDER", "Товар ещё есть")).andExpect(status().isOk());
        assertThat(jdbc.queryForObject("select count(*) from visits where uuid = ?", Integer.class, uuid)).isEqualTo(1);

        send(jwt, visit(UUID.randomUUID(), w, LocalDateTime.now().plusHours(1), "ORDER", null))
                .andExpect(status().isBadRequest());
        send(data.jwt(w.expeditor()), visit(UUID.randomUUID(), w, at, "ORDER", null)).andExpect(status().isForbidden());
    }

    @Test
    void фотоПолки_иВизитыЗаСегодняВДанныхАгента() throws Exception {
        World w = data.world("Фото полки");
        String jwt = data.jwt(w.agent());
        UUID uuid = UUID.randomUUID();
        send(jwt, visit(uuid, w, LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(10), "ORDER", null))
                .andExpect(status().isOk()).andExpect(jsonPath("$.distance").doesNotExist());

        mvc.perform(put("/api/mobile/agent/visits/{uuid}/photo", uuid).header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.IMAGE_PNG).content(new byte[]{1, 2, 3})).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Фото — только JPEG"));
        mvc.perform(put("/api/mobile/agent/visits/{uuid}/photo", uuid).header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.IMAGE_JPEG).content(JPEG)).andExpect(status().isNoContent());
        mvc.perform(put("/api/mobile/agent/visits/{uuid}/photo", UUID.randomUUID()).header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.IMAGE_JPEG).content(JPEG)).andExpect(status().isNotFound());

        String path = jdbc.queryForObject("select shelf_photo from visits where uuid = ?", String.class, uuid);
        assertThat(path).isEqualTo(w.company().getId() + "/visits/" + uuid + ".jpg");
        assertThat(Files.readAllBytes(Path.of(filesDir, path))).isEqualTo(JPEG);

        mvc.perform(get("/api/mobile/agent/data").header("Authorization", "Bearer " + jwt)).andExpect(status().isOk())
                .andExpect(jsonPath("$.visits[0].uuid").value(uuid.toString()))
                .andExpect(jsonPath("$.visits[0].result").value("ORDER"))
                .andExpect(jsonPath("$.visits[0].photo").value(true));
    }
}
