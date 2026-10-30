package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.domain.TripStatus;
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
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Торговый меняет и отменяет свой заказ, пока его не отгрузили: строки на месте, лимит заново, история, отмена с причиной. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class OrderEditApiTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private ResultActions create(String jwt, UUID uuid, World w, String payment, int qty) throws Exception {
        LocalDateTime at = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(5);
        return mvc.perform(post("/api/mobile/agent/orders").header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content("""
                        {"uuid": "%s", "outletId": %d, "createdAt": "%s", "payment": "%s", "comment": "после обеда",
                         "items": [{"productId": %d, "qty": %d}]}"""
                        .formatted(uuid, w.outlet().getId(), at, payment, w.product().getId(), qty)));
    }

    private ResultActions edit(String jwt, UUID uuid, String json) throws Exception {
        return mvc.perform(put("/api/mobile/agent/orders/{uuid}", uuid).header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private ResultActions cancel(String jwt, UUID uuid, String reason) throws Exception {
        return mvc.perform(post("/api/mobile/agent/orders/{uuid}/cancel", uuid).header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content(reason == null ? "{}" : "{\"reason\": \"" + reason + "\"}"));
    }

    private List<String> events(UUID uuid) {
        return jdbc.queryForList("select e.message from order_events e join orders o on o.id = e.order_id "
                + "where o.uuid = ? order by e.id", String.class, uuid);
    }

    @Test
    void правка_строкиНаМесте_лимитЗаново_история_ничегоНеИзменилось() throws Exception {
        World w = data.world("Правка заказа");
        data.price(w, PriceKind.WHOLESALE, 1000, data.today().minusDays(1));
        data.openingDebt(w, 80_000, data.today().minusDays(3));
        String jwt = data.jwt(w.agent());
        UUID uuid = UUID.randomUUID();
        create(jwt, uuid, w, "CASH", 10).andExpect(status().isOk()).andExpect(jsonPath("$.comment").value("после обеда"));
        String tomorrow = data.today().plusDays(1).toString();
        String json = """
                {"deliveryDate": "%s", "payment": "%s", "comment": %s, "items": [{"productId": %d, "qty": %d}],
                 "returns": %s}""";
        long p = w.product().getId();

        // тот же товар — строка меняется на месте; в долг: 80 000 + 25 000 − 3 000 = 102 000 > 100 000
        edit(jwt, uuid, json.formatted(tomorrow, "CREDIT", "null", p, 25,
                "[{\"productId\": %d, \"qty\": 3, \"reason\": \"DEFECT\"}]".formatted(p)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.total").value(25_000))
                .andExpect(jsonPath("$.returnTotal").value(3000))
                .andExpect(jsonPath("$.lines.length()").value(1))
                .andExpect(jsonPath("$.payment").value("CREDIT"))
                .andExpect(jsonPath("$.comment").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$.status").value("NEEDS_APPROVAL"));
        assertThat(events(uuid).get(1)).isEqualTo("Изменён торговым — товары: было 1 поз. на 10 000 ₸, стало 1 поз. "
                + "на 25 000 ₸; возврат: было 0 ₸, стало 3 000 ₸; оплата: Наличные → В долг; новый комментарий");

        // меньше — в лимите, разрешение больше не нужно
        edit(jwt, uuid, json.formatted(tomorrow, "CREDIT", "null", p, 20,
                "[{\"productId\": %d, \"qty\": 3, \"reason\": \"EXPIRED\"}]".formatted(p)))
                .andExpect(jsonPath("$.status").value("ACCEPTED"))
                .andExpect(jsonPath("$.returns[0].reason").value("EXPIRED"));
        assertThat(events(uuid)).last().isEqualTo("В пределах лимита — разрешение не нужно");
        int count = events(uuid).size();
        // то же самое ещё раз (повтор с телефона) — истории не прибавилось
        edit(jwt, uuid, json.formatted(tomorrow, "CREDIT", "null", p, 20,
                "[{\"productId\": %d, \"qty\": 3, \"reason\": \"EXPIRED\"}]".formatted(p)))
                .andExpect(status().isOk());
        assertThat(events(uuid)).hasSize(count);

        // без товаров и с прошедшим днём доставки — нельзя
        edit(jwt, uuid, json.formatted(tomorrow, "CASH", "null", p, 0, "[]")).andExpect(status().isBadRequest());
        edit(jwt, uuid, """
                {"deliveryDate": "%s", "payment": "CASH", "items": []}""".formatted(tomorrow))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").value("В заказе нет товаров"));

        // в данных агента — новый состав
        mvc.perform(get("/api/mobile/agent/data").header("Authorization", "Bearer " + jwt))
                .andExpect(jsonPath("$.orders[0].total").value(20_000))
                .andExpect(jsonPath("$.orders[0].lines[0].qty").value(20));
    }

    @Test
    void отмена_сПричиной_повтор_отгруженныйНельзя_чужойНельзя() throws Exception {
        World w = data.world("Отмена заказа");
        data.price(w, PriceKind.WHOLESALE, 1000, data.today().minusDays(1));
        String jwt = data.jwt(w.agent());
        UUID first = UUID.randomUUID(), second = UUID.randomUUID();
        create(jwt, first, w, "CASH", 5).andExpect(status().isOk());
        create(jwt, second, w, "CASH", 7).andExpect(status().isOk());

        cancel(jwt, first, " ").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Укажите, почему отменяете заказ"));
        cancel(jwt, first, "Клиент передумал").andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("CANCELLED"))
                .andExpect(jsonPath("$.note").value("Отменён торговым: Клиент передумал"));
        cancel(jwt, first, "Ещё раз").andExpect(status().isOk()).andExpect(jsonPath("$.status").value("CANCELLED"));
        assertThat(events(first)).hasSize(2);
        edit(jwt, first, """
                {"payment": "CASH", "items": [{"productId": %d, "qty": 1}]}""".formatted(w.product().getId()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(
                        "Заказ З-" + data.today().format(DateTimeFormatter.ofPattern("ddMMyy"))
                                + "-1 уже «Отменён» — изменить или отменить его может только оператор"));

        // другой торговый — не его заказ
        String other = data.jwt(data.person(w, "Агент 2", Role.AGENT));
        cancel(other, second, "Ошибка").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Это заказ другого сотрудника"));

        // отгрузили экспедитору — только оператор
        data.stockIn(w, 100);
        data.trip(w, TripStatus.ON_ROAD, data.orderByUuid(second));
        cancel(jwt, second, "Клиент передумал").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.endsWith(
                        "уже «Отгружен» — изменить или отменить его может только оператор")));
        cancel(jwt, UUID.randomUUID(), "Нет такого").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Заказ ещё не дошёл до сервера — попробуйте через минуту"));
    }
}
