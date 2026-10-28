package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Role;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Новый магазин от агента: «на проверке», в конце его маршрута, лимит нового магазина, повтор без дубля, фасад. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class OutletApiTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private ResultActions send(String jwt, String json) throws Exception {
        return mvc.perform(post("/api/mobile/agent/outlets").header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private static String outlet(UUID uuid, World w, String phone, String address, String landmark) {
        return """
                {"uuid": "%s", "routeId": %d, "name": "Магазин «Новый»", "owner": "Айгерим", "phone": "%s",
                 "address": %s, "landmark": %s, "lat": 42.35, "lng": 69.61, "priceKind": "RETAIL"}"""
                .formatted(uuid, w.route().getId(), phone, address == null ? "null" : '"' + address + '"',
                        landmark == null ? "null" : '"' + landmark + '"');
    }

    @Test
    void наПроверке_вКонцеМаршрута_повторБезДубля() throws Exception {
        World w = data.world("Новый магазин");
        String jwt = data.jwt(w.agent());
        UUID uuid = UUID.randomUUID();

        send(jwt, outlet(uuid, w, "87011234567", null, null)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Укажите адрес или ориентир"));
        send(jwt, outlet(uuid, w, "123", "ул. Абая, 5", null)).andExpect(status().isBadRequest());
        send(jwt, outlet(uuid, w, "87011234567", null, "у мечети, зелёные ворота")).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.phone").value("+7 701 123 45 67"))
                .andExpect(jsonPath("$.priceKind").value("RETAIL"))
                .andExpect(jsonPath("$.creditLimit").value(50000))
                .andExpect(jsonPath("$.landmark").value("у мечети, зелёные ворота"));
        send(jwt, outlet(uuid, w, "87011234567", null, "у мечети")).andExpect(status().isOk());

        Map<String, Object> row = jdbc.queryForMap("select o.id, o.created_by, ro.route_id, ro.position from outlets o "
                + "join route_outlets ro on ro.outlet_id = o.id where o.uuid = ?", uuid);
        assertThat(row.get("created_by")).isEqualTo(w.agent().getName());
        assertThat(row.get("route_id")).isEqualTo(w.route().getId());
        assertThat(row.get("position")).isEqualTo(1); // после магазина мира на позиции 0
        assertThat(jdbc.queryForObject("select count(*) from outlets where uuid = ?", Integer.class, uuid)).isEqualTo(1);

        mvc.perform(get("/api/mobile/agent/data").header("Authorization", "Bearer " + jwt))
                .andExpect(jsonPath("$.routes[0].outlets.length()").value(2))
                .andExpect(jsonPath("$.outlets[1].status").value("PENDING"));

        mvc.perform(put("/api/mobile/agent/outlets/{uuid}/photo", uuid).header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.IMAGE_JPEG).content(VisitApiTest.JPEG)).andExpect(status().isNoContent());
        assertThat(jdbc.queryForObject("select facade_photo from outlets where uuid = ?", String.class, uuid))
                .isEqualTo(w.id() + "/outlets/" + uuid + ".jpg");
        // магазин не на его маршруте
        String other = data.jwt(data.person(w, "Другой агент", Role.AGENT));
        mvc.perform(put("/api/mobile/agent/outlets/{uuid}/photo", w.outlet().getUuid()).header("Authorization", "Bearer " + other)
                .contentType(MediaType.IMAGE_JPEG).content(VisitApiTest.JPEG)).andExpect(status().isNotFound());
    }
}
