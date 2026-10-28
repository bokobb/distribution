package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.PaymentMethod;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import org.junit.jupiter.api.BeforeEach;
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
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Возврат негодного товара экспедитором с телефона: товар в машину, долг меньше по цене дня, повтор без дубля. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class ReturnApiTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    World w;
    Order order;
    Trip trip;

    /** Магазин (опт) с долгом 30 000 и заказом в рейсе; опт вчера — 900, с сегодня — 950; в машине 10 шт. */
    @BeforeEach
    void setUp() {
        w = data.world("Возврат");
        data.stockIn(w, 100);
        data.openingDebt(w, 30_000, data.today().minusDays(20));
        data.price(w, PriceKind.WHOLESALE, 900, data.today().minusDays(10));
        data.price(w, PriceKind.WHOLESALE, 950, data.today());
        data.price(w, PriceKind.RETAIL, 1_200, data.today().minusDays(10));
        order = data.order(w, data.today(), PaymentMethod.CASH, 10, 1_000);
        trip = data.trip(w, TripStatus.ON_ROAD, order);
    }

    private ResultActions send(String jwt, String json) throws Exception {
        return mvc.perform(post("/api/mobile/expeditor/returns").header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private ResultActions send(String json) throws Exception {
        return send(data.jwt(w.expeditor()), json);
    }

    private String back(UUID uuid, Long outletId, LocalDateTime at, String lines) {
        return """
                {"uuid": "%s", "outletId": %d, "tripId": %d, "returnedAt": "%s", "lines": %s}"""
                .formatted(uuid, outletId, trip.getId(), at, lines);
    }

    private String back(LocalDateTime at, int qty, String reason) {
        return back(UUID.randomUUID(), w.outlet().getId(), at, line(qty, reason));
    }

    private String line(int qty, String reason) {
        return """
                [{"productId": %d, "qty": %d, "reason": "%s"}]""".formatted(w.product().getId(), qty, reason);
    }

    private static LocalDateTime earlier() {
        return LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(5);
    }

    private int returns() {
        return jdbc.queryForObject("select count(*) from returns where outlet_id = ?", Integer.class, w.outlet().getId());
    }

    @Test
    void бракВМашину_долгМеньшеПоЦенеДня_повторБезДубля() throws Exception {
        UUID uuid = UUID.randomUUID();
        String json = back(uuid, w.outlet().getId(), earlier(), line(3, "DEFECT"));
        send(json).andExpect(status().isOk())
                .andExpect(jsonPath("$.total").value(2_850))
                .andExpect(jsonPath("$.debt").value(27_150))
                .andExpect(jsonPath("$.lines[0].price").value(950))
                .andExpect(jsonPath("$.lines[0].reasonLabel").value("Брак"));
        send(json).andExpect(status().isOk()).andExpect(jsonPath("$.debt").value(27_150));

        assertThat(returns()).isEqualTo(1);
        assertThat(data.balance(w.car(), w.product())).isEqualTo(13);
        assertThat(jdbc.queryForObject("select order_id from returns where uuid = ?", Long.class, uuid)).isEqualTo(order.getId());
        assertThat(jdbc.queryForObject("select count(*) from stock_movements where reason = 'RETURN' and trip_id = ?",
                Integer.class, trip.getId())).isEqualTo(1);
    }

    @Test
    void ценаНаДеньВозврата() throws Exception {
        send(back(earlier().minusDays(1), 2, "EXPIRED")).andExpect(status().isOk())
                .andExpect(jsonPath("$.lines[0].price").value(900))
                .andExpect(jsonPath("$.lines[0].reasonLabel").value("Просрочка"))
                .andExpect(jsonPath("$.debt").value(28_200));
    }

    @Test
    void ошибкиНичегоНеЗаписывают() throws Exception {
        send(back(UUID.randomUUID(), w.outlet().getId(), earlier(), "[]")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("В возврате нет товаров"));
        send(back(earlier(), 0, "DEFECT")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("Неверное количество")));
        send(back(earlier(), 1, "ДРУГОЕ")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("причину возврата")));
        send(back(earlier().minusDays(30), 1, "DEFECT")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("Нет цены")));
        send(back(LocalDateTime.now().plusHours(1), 1, "DEFECT")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("Время возврата неверное")));
        Outlet elsewhere = data.outletInNewRegion(w, w.agent());
        send(back(UUID.randomUUID(), elsewhere.getId(), earlier(), line(1, "DEFECT"))).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("Магазина нет в рейсе")));
        send(data.jwt(data.person(w, "Чужой экспедитор", Role.EXPEDITOR)), back(earlier(), 1, "DEFECT"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message", containsString("не ваш рейс")));
        send(data.jwt(w.agent()), back(earlier(), 1, "DEFECT")).andExpect(status().isForbidden());
        data.setTripStatus(trip, TripStatus.CLOSED);
        send(back(earlier(), 1, "DEFECT")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("уже закрыт")));

        assertThat(returns()).isZero();
        assertThat(data.balance(w.car(), w.product())).isEqualTo(10);
    }
}
