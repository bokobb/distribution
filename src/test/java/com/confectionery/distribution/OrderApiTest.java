package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.PriceKind;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Заказ агента с телефона: цены сервера, номер, повтор без дубля, долг сверх лимита, оплата по настройкам. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class OrderApiTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private ResultActions send(String jwt, String json) throws Exception {
        return mvc.perform(post("/api/mobile/agent/orders").header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private static String order(UUID uuid, World w, String payment, int qty, LocalDate delivery) {
        LocalDateTime at = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(5);
        return """
                {"uuid": "%s", "outletId": %d, "createdAt": "%s", "deliveryDate": %s, "payment": "%s",
                 "comment": "после обеда", "items": [{"productId": %d, "qty": %d}]}"""
                .formatted(uuid, w.outlet().getId(), at, delivery == null ? "null" : '"' + delivery.toString() + '"',
                        payment, w.product().getId(), qty);
    }

    @Test
    void ценыСервера_номер_повторБезДубля_вДанныхАгента() throws Exception {
        World w = data.world("Заказ");
        data.price(w, PriceKind.WHOLESALE, 450, data.today().minusDays(10));
        data.price(w, PriceKind.WHOLESALE, 500, data.today().minusDays(1));
        data.price(w, PriceKind.RETAIL, 650, data.today().minusDays(1));
        String jwt = data.jwt(w.agent());
        UUID uuid = UUID.randomUUID();
        String number = "З-" + data.today().format(DateTimeFormatter.ofPattern("ddMMyy")) + "-1";

        send(jwt, order(uuid, w, "CASH", 12, null)).andExpect(status().isOk())
                .andExpect(jsonPath("$.number").value(number))
                .andExpect(jsonPath("$.status").value("ACCEPTED"))
                .andExpect(jsonPath("$.statusLabel").value("Принят"))
                .andExpect(jsonPath("$.deliveryDate").value(data.today().plusDays(1).toString()))
                .andExpect(jsonPath("$.total").value(6000))
                .andExpect(jsonPath("$.lines[0].price").value(500));
        send(jwt, order(uuid, w, "CASH", 99, null)).andExpect(status().isOk())
                .andExpect(jsonPath("$.number").value(number)).andExpect(jsonPath("$.total").value(6000));
        assertThat(jdbc.queryForObject("select count(*) from orders where uuid = ?", Integer.class, uuid)).isEqualTo(1);
        send(jwt, order(UUID.randomUUID(), w, "KASPI", 1, data.today())).andExpect(status().isOk())
                .andExpect(jsonPath("$.number").value(number.replaceAll("1$", "2")));

        mvc.perform(get("/api/mobile/agent/data").header("Authorization", "Bearer " + jwt))
                .andExpect(jsonPath("$.orders.length()").value(2))
                .andExpect(jsonPath("$.orders[0].uuid").value(uuid.toString()));
    }

    @Test
    void вДолгСверхЛимита_нужноРазрешение() throws Exception {
        World w = data.world("Лимит");
        data.price(w, PriceKind.WHOLESALE, 1000, data.today().minusDays(1));
        data.openingDebt(w, 80_000, data.today().minusDays(3));
        String jwt = data.jwt(w.agent());

        send(jwt, order(UUID.randomUUID(), w, "CREDIT", 15, null)).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ACCEPTED"));
        // долг 80 000 + не доставлено 15 000 + этот 10 000 > лимита 100 000
        send(jwt, order(UUID.randomUUID(), w, "CREDIT", 10, null)).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("NEEDS_APPROVAL"))
                .andExpect(jsonPath("$.note").value("Долг сверх лимита — ждёт разрешения оператора"));
        assertThat(jdbc.queryForObject("select e.message from order_events e join orders o on o.id = e.order_id "
                + "where o.status = 'NEEDS_APPROVAL' and o.company_id = ? and e.who_name = 'Система'", String.class, w.id()))
                .isEqualTo("Долг 80 000 ₸ + не доставлено 15 000 ₸ + этот заказ 10 000 ₸ = 105 000 ₸ при лимите 100 000 ₸ — нужно разрешение");
        // за наличные лимит не проверяется
        send(jwt, order(UUID.randomUUID(), w, "CASH", 50, null)).andExpect(jsonPath("$.status").value("ACCEPTED"));
    }

    @Test
    void оплатаИДатаПоНастройкам_нетЦены() throws Exception {
        World w = data.world("Настройки заказа");
        String jwt = data.jwt(w.agent());
        send(jwt, order(UUID.randomUUID(), w, "CASH", 1, null)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Нет цены на «" + w.product().getName() + "» — обратитесь к оператору"));

        data.price(w, PriceKind.WHOLESALE, 1000, data.today().minusDays(1));
        jdbc.update("insert into company_settings (company_id, allow_credit, accept_kaspi) values (?, false, false)", w.id());
        send(jwt, order(UUID.randomUUID(), w, "CREDIT", 1, null)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Продажа в долг выключена — выберите другую оплату"));
        send(jwt, order(UUID.randomUUID(), w, "KASPI", 1, null)).andExpect(status().isBadRequest());
        send(jwt, order(UUID.randomUUID(), w, "CASH", 1, data.today().plusDays(30))).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Дата доставки — с дня заказа и не дальше 14 дней"));
        send(jwt, order(UUID.randomUUID(), w, "CASH", 0, null)).andExpect(status().isBadRequest());
        send(data.jwt(w.expeditor()), order(UUID.randomUUID(), w, "CASH", 1, null)).andExpect(status().isForbidden());
        assertThat(jdbc.queryForObject("select count(*) from orders where company_id = ?", Integer.class, w.id())).isZero();
    }
}
