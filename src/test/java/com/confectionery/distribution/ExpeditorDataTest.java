package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.PaymentMethod;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Данные экспедитора для работы без сети: только его незакрытые рейсы, точки с заказами и долгами, товары с ценами. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class ExpeditorDataTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private ResultActions expeditorData(Employee e) throws Exception {
        return mvc.perform(get("/api/mobile/expeditor/data").header("Authorization", "Bearer " + data.jwt(e)));
    }

    @Test
    void экспедиторПолучаетСвойРейсТочкиЗаказыИДолги() throws Exception {
        World w = data.world("Экспедитор рейс");
        data.stockIn(w, 100);
        data.price(w, PriceKind.WHOLESALE, 500, data.today());
        data.openingDebt(w, 20_000, data.today().minusDays(30));
        Order first = data.order(w, data.today(), PaymentMethod.CASH, 10, 1_000);
        Order second = data.order(w, data.today(), PaymentMethod.CREDIT, 4, 1_000);
        Trip t = data.trip(w, TripStatus.ON_ROAD, first, second);
        data.delivered(w, first, t, 8, data.today().atTime(10, 0));
        data.payment(w, first, t, PaymentMethod.CASH, 8_000, data.today().atTime(10, 0));
        data.payment(w, null, t, PaymentMethod.KASPI, 3_000, data.today().atTime(10, 5)); // в счёт долга
        data.productReturn(w, t, 2, 500, data.today());

        expeditorData(w.expeditor()).andExpect(status().isOk())
                .andExpect(jsonPath("$.date").value(data.today().toString()))
                .andExpect(jsonPath("$.company.name").value(w.company().getName()))
                .andExpect(jsonPath("$.settings.acceptKaspi").isBoolean())
                .andExpect(jsonPath("$.products[0].wholesale").value(500))
                .andExpect(jsonPath("$.trips", hasSize(1)))
                .andExpect(jsonPath("$.trips[0].number").value(t.getNumber()))
                .andExpect(jsonPath("$.trips[0].statusLabel").value("В пути"))
                .andExpect(jsonPath("$.trips[0].stops", hasSize(2)))
                .andExpect(jsonPath("$.trips[0].stops[0].position").value(0))
                .andExpect(jsonPath("$.trips[0].stops[0].outlet.name").value(w.outlet().getName()))
                .andExpect(jsonPath("$.trips[0].stops[0].outlet.debt").value(20_000 + 8_000 - 8_000 - 3_000 - 1_000))
                .andExpect(jsonPath("$.trips[0].cash.cash").value(8_000))
                .andExpect(jsonPath("$.trips[0].cash.kaspi").value(3_000))
                .andExpect(jsonPath("$.trips[0].cash.oldDebt").value(3_000))
                .andExpect(jsonPath("$.trips[0].cash.returnsQty").value(2))
                .andExpect(jsonPath("$.trips[0].cash.returnsTotal").value(1_000))
                .andExpect(jsonPath("$.trips[0].stops[0].order.number").value(first.getNumber()))
                .andExpect(jsonPath("$.trips[0].stops[0].order.status").value("PARTIAL"))
                .andExpect(jsonPath("$.trips[0].stops[0].order.total").value(10_000))
                .andExpect(jsonPath("$.trips[0].stops[0].order.paid").value(8_000))
                .andExpect(jsonPath("$.trips[0].stops[0].order.lines[0].qty").value(10))
                .andExpect(jsonPath("$.trips[0].stops[0].order.lines[0].price").value(1_000))
                .andExpect(jsonPath("$.trips[0].stops[0].order.lines[0].delivered").value(8))
                .andExpect(jsonPath("$.trips[0].stops[1].order.payment").value("CREDIT"))
                .andExpect(jsonPath("$.trips[0].stops[1].order.paid").value(0))
                .andExpect(jsonPath("$.trips[0].stops[1].order.lines[0].delivered").doesNotExist());

        // другой экспедитор этот рейс не видит; закрытый рейс уходит с телефона
        Employee other = data.person(w, "Другой экспедитор", Role.EXPEDITOR);
        expeditorData(other).andExpect(jsonPath("$.trips", empty()));
        jdbc.update("update trips set status = 'CLOSED' where id = ?", t.getId());
        expeditorData(w.expeditor()).andExpect(jsonPath("$.trips", empty()));
    }

    @Test
    void рейсНаПослезавтраЕщёНеВиден() throws Exception {
        World w = data.world("Экспедитор завтра");
        data.stockIn(w, 100);
        Trip tomorrow = data.trip(w, TripStatus.ON_ROAD, data.order(w, data.today().plusDays(1), PaymentMethod.CASH, 1, 100));
        Trip later = data.trip(w, TripStatus.ON_ROAD, data.order(w, data.today().plusDays(2), PaymentMethod.CASH, 1, 100));
        jdbc.update("update trips set trip_date = ? where id = ?", data.today().plusDays(1), tomorrow.getId());
        jdbc.update("update trips set trip_date = ? where id = ?", data.today().plusDays(2), later.getId());

        expeditorData(w.expeditor()).andExpect(jsonPath("$.trips", hasSize(1)))
                .andExpect(jsonPath("$.trips[0].id").value(tomorrow.getId()));
    }

    @Test
    void агентуДанныеЭкспедитораЗакрыты() throws Exception {
        World w = data.world("Агент не экспедитор");
        expeditorData(w.agent()).andExpect(status().isForbidden());
    }
}
