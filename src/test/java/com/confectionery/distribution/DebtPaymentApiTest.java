package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.PaymentMethod;
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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Оплата старого долга экспедитором с телефона: в кассу рейса, долг уменьшается, повтор без дубля. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class DebtPaymentApiTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    World w;
    Trip trip;

    /** Магазин с долгом 30 000 и заказом в рейсе экспедитора. */
    @BeforeEach
    void setUp() {
        w = data.world("Оплата долга");
        data.stockIn(w, 100);
        data.openingDebt(w, 30_000, data.today().minusDays(20));
        Order order = data.order(w, data.today(), PaymentMethod.CASH, 10, 1_000);
        trip = data.trip(w, TripStatus.ON_ROAD, order);
    }

    private ResultActions send(String jwt, String json) throws Exception {
        return mvc.perform(post("/api/mobile/expeditor/payments").header("Authorization", "Bearer " + jwt)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    private ResultActions send(String json) throws Exception {
        return send(data.jwt(w.expeditor()), json);
    }

    private String pay(UUID uuid, Long outletId, String method, long amount, LocalDateTime at) {
        return """
                {"uuid": "%s", "outletId": %d, "tripId": %d, "method": "%s", "amount": %d, "paidAt": "%s"}"""
                .formatted(uuid, outletId, trip.getId(), method, amount, at);
    }

    private String pay(String method, long amount) {
        return pay(UUID.randomUUID(), w.outlet().getId(), method, amount, earlier());
    }

    private static LocalDateTime earlier() {
        return LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(5);
    }

    private int oldDebtPayments() {
        return jdbc.queryForObject("select count(*) from payments where order_id is null and outlet_id = ?", Integer.class,
                w.outlet().getId());
    }

    @Test
    void оплатаДолгаВКассуРейса_повторБезДубля() throws Exception {
        UUID uuid = UUID.randomUUID();
        String json = pay(uuid, w.outlet().getId(), "CASH", 20_000, earlier());
        send(json).andExpect(status().isOk())
                .andExpect(jsonPath("$.outletId").value(w.outlet().getId()))
                .andExpect(jsonPath("$.method").value("CASH"))
                .andExpect(jsonPath("$.amount").value(20_000))
                .andExpect(jsonPath("$.debt").value(10_000));
        send(json).andExpect(status().isOk()).andExpect(jsonPath("$.debt").value(10_000));

        assertThat(oldDebtPayments()).isEqualTo(1);
        assertThat(jdbc.queryForObject("select trip_id from payments where uuid = ?", Long.class, uuid)).isEqualTo(trip.getId());
        send(pay("KASPI", 4_000)).andExpect(status().isOk()).andExpect(jsonPath("$.debt").value(6_000));
        mvc.perform(get("/api/mobile/expeditor/data").header("Authorization", "Bearer " + data.jwt(w.expeditor())))
                .andExpect(jsonPath("$.trips[0].stops[0].outlet.debt").value(6_000));
    }

    @Test
    void большеДолга_остатокАвансом() throws Exception {
        send(pay("CASH", 35_000)).andExpect(status().isOk()).andExpect(jsonPath("$.debt").value(-5_000));
    }

    @Test
    void ошибкиНичегоНеЗаписывают() throws Exception {
        send(pay("CASH", 0)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Сумма оплаты должна быть больше нуля"));
        send(pay("CREDIT", 1_000)).andExpect(status().isBadRequest());
        send(pay(UUID.randomUUID(), w.outlet().getId(), "CASH", 1_000, LocalDateTime.now().plusHours(1)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message", containsString("Время оплаты неверное")));
        Outlet elsewhere = data.outletInNewRegion(w, w.agent());
        send(pay(UUID.randomUUID(), elsewhere.getId(), "CASH", 1_000, earlier())).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("Магазина нет в рейсе")));
        send(data.jwt(data.person(w, "Чужой экспедитор", Role.EXPEDITOR)), pay("CASH", 1_000))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message", containsString("не ваш рейс")));
        send(data.jwt(w.agent()), pay("CASH", 1_000)).andExpect(status().isForbidden());
        jdbc.update("insert into company_settings (company_id, accept_kaspi) values (?, false)", w.id());
        send(pay("KASPI", 1_000)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Kaspi компания не принимает"));
        data.setTripStatus(trip, TripStatus.CLOSED);
        send(pay("CASH", 1_000)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message", containsString("уже закрыт")));

        assertThat(oldDebtPayments()).isZero();
    }
}
