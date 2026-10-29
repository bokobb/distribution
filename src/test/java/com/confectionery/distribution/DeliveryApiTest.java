package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.PaymentMethod;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.formLogin;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Выдача заказа экспедитором с телефона: всё, частично, отказ; деньги за заказ; товар из машины; повтор без дубля. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class DeliveryApiTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;
    @Value("${distribution.files.dir}")
    String filesDir;

    World w;
    Order order;
    Trip trip;

    /** Заказ 10 шт по 1 000 наличными в рейсе экспедитора: в машине 10 шт. */
    @BeforeEach
    void setUp() {
        w = data.world("Выдача");
        data.stockIn(w, 100);
        order = data.order(w, data.today(), PaymentMethod.CASH, 10, 1_000);
        trip = data.trip(w, TripStatus.ON_ROAD, order);
    }

    private ResultActions send(String json) throws Exception {
        return mvc.perform(post("/api/mobile/expeditor/deliveries").header("Authorization", "Bearer " + data.jwt(w.expeditor()))
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private String delivery(UUID uuid, String items, String payments) {
        LocalDateTime at = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(5);
        return """
                {"uuid": "%s", "orderId": %d, "deliveredAt": "%s", "refused": false, "lat": 42.3, "lng": 69.6,
                 "items": %s, "payments": %s}""".formatted(uuid, order.getId(), at, items, payments);
    }

    private String pay(String method, long amount) {
        return """
                [{"uuid": "%s", "method": "%s", "amount": %d}]""".formatted(UUID.randomUUID(), method, amount);
    }

    private String item(int qty) {
        return """
                [{"productId": %d, "qty": %d}]""".formatted(w.product().getId(), qty);
    }

    private int count(String sql) {
        return jdbc.queryForObject(sql, Integer.class, order.getId());
    }

    @Test
    void выданоВсё_оплаченоНаличными_повторБезДубля() throws Exception {
        UUID uuid = UUID.randomUUID();
        String json = delivery(uuid, "[]", pay("CASH", 10_000));
        send(json).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DELIVERED"))
                .andExpect(jsonPath("$.statusLabel").value("Доставлен"))
                .andExpect(jsonPath("$.total").value(10_000))
                .andExpect(jsonPath("$.paid").value(10_000));
        send(json).andExpect(status().isOk()).andExpect(jsonPath("$.paid").value(10_000));

        assertThat(count("select count(*) from deliveries where order_id = ?")).isEqualTo(1);
        assertThat(count("select count(*) from payments where order_id = ?")).isEqualTo(1);
        assertThat(data.balance(w.car(), w.product())).isZero();
        assertThat(jdbc.queryForObject("select lat from deliveries where uuid = ?", Double.class, uuid)).isEqualTo(42.3);

        mvc.perform(get("/api/mobile/expeditor/data").header("Authorization", "Bearer " + data.jwt(w.expeditor())))
                .andExpect(jsonPath("$.trips[0].stops[0].order.status").value("DELIVERED"))
                .andExpect(jsonPath("$.trips[0].stops[0].order.paid").value(10_000))
                .andExpect(jsonPath("$.trips[0].stops[0].order.lines[0].delivered").value(10))
                .andExpect(jsonPath("$.trips[0].stops[0].outlet.debt").value(0));
    }

    @Test
    void частично_недоплатаУходитВДолг() throws Exception {
        send(delivery(UUID.randomUUID(), item(6), pay("CASH", 5_000))).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("PARTIAL"))
                .andExpect(jsonPath("$.total").value(6_000))
                .andExpect(jsonPath("$.paid").value(5_000));

        assertThat(data.balance(w.car(), w.product())).isEqualTo(4);
        assertThat(jdbc.queryForObject("select status from orders where id = ?", String.class, order.getId())).isEqualTo("PARTIAL");
        assertThat(count("select count(*) from order_events where order_id = ? and message like 'Недоплата%'")).isEqualTo(1);
        mvc.perform(get("/api/mobile/expeditor/data").header("Authorization", "Bearer " + data.jwt(w.expeditor())))
                .andExpect(jsonPath("$.trips[0].stops[0].outlet.debt").value(1_000));
    }

    @Test
    void отказМагазинаСПричиной() throws Exception {
        String refused = """
                {"uuid": "%s", "orderId": %d, "refused": true, "refuseReason": "%s", "items": [], "payments": []}""";
        send(refused.formatted(UUID.randomUUID(), order.getId(), " ")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Укажите, почему магазин отказался"));
        send(refused.formatted(UUID.randomUUID(), order.getId(), "Закрыто на ремонт")).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("REFUSED"))
                .andExpect(jsonPath("$.total").value(0));

        assertThat(data.balance(w.car(), w.product())).isEqualTo(10);
        assertThat(jdbc.queryForObject("select refuse_reason from orders where id = ?", String.class, order.getId()))
                .isEqualTo("Закрыто на ремонт");
        assertThat(count("select count(*) from payments where order_id = ?")).isZero();
    }

    @Test
    void ошибкиНичегоНеЗаписывают() throws Exception {
        send(delivery(UUID.randomUUID(), item(11), "[]")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("больше, чем в заказе")));
        send(delivery(UUID.randomUUID(), item(0), "[]")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Ничего не выдано — отметьте отказ магазина"));
        send(delivery(UUID.randomUUID(), "[]", pay("CASH", 10_001))).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("больше выданного")));
        send(delivery(UUID.randomUUID(), "[]", pay("CREDIT", 100))).andExpect(status().isBadRequest());
        jdbc.update("insert into company_settings (company_id, accept_kaspi) values (?, false)", w.id());
        send(delivery(UUID.randomUUID(), "[]", pay("KASPI", 100))).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Kaspi компания не принимает"));

        assertThat(count("select count(*) from deliveries where order_id = ?")).isZero();
        assertThat(count("select count(*) from payments where order_id = ?")).isZero();
        assertThat(data.balance(w.car(), w.product())).isEqualTo(10);
        assertThat(jdbc.queryForObject("select status from orders where id = ?", String.class, order.getId())).isEqualTo("IN_TRIP");

        // чужой экспедитор и агент
        String other = data.jwt(data.person(w, "Чужой экспедитор", Role.EXPEDITOR));
        mvc.perform(post("/api/mobile/expeditor/deliveries").header("Authorization", "Bearer " + other)
                        .contentType(MediaType.APPLICATION_JSON).content(delivery(UUID.randomUUID(), "[]", "[]")))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message", containsString("нет в вашем рейсе")));
        mvc.perform(post("/api/mobile/expeditor/deliveries").header("Authorization", "Bearer " + data.jwt(w.agent()))
                        .contentType(MediaType.APPLICATION_JSON).content(delivery(UUID.randomUUID(), "[]", "[]")))
                .andExpect(status().isForbidden());

        // после выдачи — второй раз другой выдачей нельзя
        send(delivery(UUID.randomUUID(), "[]", "[]")).andExpect(status().isOk());
        send(delivery(UUID.randomUUID(), "[]", "[]")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("уже «Доставлен»")));
    }

    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 13, 10, 26, 10, 1, 2};
    private static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 1, 2, 3};

    private ResultActions proof(UUID uuid, String jwt, MediaType type, byte[] body) throws Exception {
        return mvc.perform(put("/api/mobile/expeditor/deliveries/{uuid}/proof", uuid).header("Authorization", "Bearer " + jwt)
                .contentType(type).content(body));
    }

    @Test
    void подписьИлиФотоНакладной_послеВыдачи_видныВАдминке() throws Exception {
        UUID uuid = UUID.randomUUID();
        String jwt = data.jwt(w.expeditor());
        proof(uuid, jwt, MediaType.IMAGE_PNG, PNG).andExpect(status().isNotFound()); // выдачи ещё нет
        send(delivery(uuid, "[]", pay("CASH", 10_000))).andExpect(status().isOk());

        proof(uuid, jwt, MediaType.IMAGE_GIF, new byte[]{'G', 'I', 'F'}).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Подтверждение — только фото JPEG или подпись PNG"));
        proof(uuid, jwt, MediaType.IMAGE_PNG, PNG).andExpect(status().isNoContent());
        String path = jdbc.queryForObject("select proof from deliveries where uuid = ?", String.class, uuid);
        assertThat(path).isEqualTo(w.company().getId() + "/deliveries/" + uuid + ".png");
        assertThat(Files.readAllBytes(Path.of(filesDir, path))).isEqualTo(PNG);

        // переснял фотографией — подпись больше не нужна
        proof(uuid, jwt, MediaType.IMAGE_JPEG, JPEG).andExpect(status().isNoContent());
        String photo = jdbc.queryForObject("select proof from deliveries where uuid = ?", String.class, uuid);
        assertThat(photo).endsWith(uuid + ".jpg");
        assertThat(Path.of(filesDir, path)).doesNotExist();

        World other = data.world("Чужое подтверждение");
        proof(uuid, data.jwt(other.expeditor()), MediaType.IMAGE_JPEG, JPEG).andExpect(status().isNotFound());

        data.password(w.operator(), "Проверка-2026", false);
        MockHttpSession s = (MockHttpSession) mvc.perform(formLogin("/login").user(w.operator().getPhone()).password("Проверка-2026"))
                .andReturn().getRequest().getSession(false);
        mvc.perform(get("/admin/trips/{id}", trip.getId()).session(s)).andExpect(status().isOk())
                .andExpect(content().string(containsString("/admin/trips/proof/" + uuid)))
                .andExpect(content().string(containsString("Фото накладной")));
        mvc.perform(get("/admin/orders/{id}", order.getId()).session(s)).andExpect(status().isOk())
                .andExpect(content().string(containsString("/admin/trips/proof/" + uuid)));
        mvc.perform(get("/admin/trips/proof/{uuid}", uuid).session(s)).andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_JPEG)).andExpect(content().bytes(JPEG));
    }

    @Test
    void приОтказеПодтверждениеНеНужно() throws Exception {
        UUID uuid = UUID.randomUUID();
        LocalDateTime at = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(5);
        send("""
                {"uuid": "%s", "orderId": %d, "deliveredAt": "%s", "refused": true, "refuseReason": "Закрыто",
                 "items": [], "payments": []}""".formatted(uuid, order.getId(), at)).andExpect(status().isOk());
        proof(uuid, data.jwt(w.expeditor()), MediaType.IMAGE_PNG, PNG).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("При отказе подтверждение не нужно"));
    }
}
