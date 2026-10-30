package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.formLogin;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Страница «Заказы»: фильтры из адреса доходят до списка, чужие заказы не видны. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class AdminOrderListTest {

    private static final String PASSWORD = "Проверка-2026";

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    org.springframework.jdbc.core.JdbcTemplate jdbc;

    private MockHttpSession login(Employee e) throws Exception {
        data.password(e, PASSWORD, false);
        MvcResult r = mvc.perform(formLogin("/login").user(e.getPhone()).password(PASSWORD)).andExpect(redirectedUrl("/admin")).andReturn();
        return (MockHttpSession) r.getRequest().getSession(false);
    }

    @Test
    void фильтрыТорговыйДатаЭкспедитор() throws Exception {
        World w = data.world("Страница");
        Employee agent2 = data.person(w, "Шамолхон", Role.AGENT);
        Outlet outlet2 = data.outletInNewRegion(w, agent2);
        data.stockIn(w, 100);
        Order mine = data.order(w, data.today().plusDays(1), PaymentMethod.CASH, 2, 1000);
        Order other = data.order(w, outlet2, agent2, data.today().plusDays(1), PaymentMethod.CASH, 3, 1000);
        Order shipped = data.order(w, outlet2, agent2, data.today().plusDays(1), PaymentMethod.CASH, 1, 1000);
        data.trip(w, TripStatus.LOADING, shipped);
        Order old = data.order(w, data.today(), PaymentMethod.CASH, 1, 1000);
        LocalDate oldDay = data.today().minusDays(2);
        jdbc.update("update orders set created_at = created_at - interval '2 days' where id = ?", old.getId());
        Order foreign = data.order(data.world("Чужая"), data.today().plusDays(1), PaymentMethod.CASH, 1, 1000);
        MockHttpSession s = login(w.operator());

        // по умолчанию — заказы, пришедшие сегодня, все торговые; чужой компании нет
        mvc.perform(get("/admin/orders").session(s)).andExpect(status().isOk())
                .andExpect(content().string(containsString(mine.getNumber())))
                .andExpect(content().string(containsString(other.getNumber())))
                .andExpect(content().string(not(containsString(old.getNumber()))))
                .andExpect(content().string(not(containsString(foreign.getNumber()))))
                .andExpect(content().string(containsString("Шамолхон")));

        mvc.perform(get("/admin/orders").session(s).param("agent", agent2.getId().toString()).param("exp", "none"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString(other.getNumber())))
                .andExpect(content().string(not(containsString(mine.getNumber()))))
                .andExpect(content().string(not(containsString(shipped.getNumber()))));

        mvc.perform(get("/admin/orders").session(s).param("exp", w.expeditor().getId().toString()))
                .andExpect(content().string(containsString(shipped.getNumber())))
                .andExpect(content().string(not(containsString(other.getNumber()))));

        mvc.perform(get("/admin/orders").session(s).param("day", "range")
                        .param("from", oldDay.toString()).param("to", oldDay.toString()))
                .andExpect(content().string(containsString(old.getNumber())))
                .andExpect(content().string(not(containsString(mine.getNumber()))));

        // ссылки статусов и быстрых дат сохраняют выбранные условия
        mvc.perform(get("/admin/orders").session(s).param("agent", agent2.getId().toString()).param("size", "25"))
                .andExpect(content().string(containsString("agent=" + agent2.getId() + "&amp;size=25&amp;status=IN_TRIP")))
                .andExpect(content().string(containsString("agent=" + agent2.getId() + "&amp;size=25&amp;day=today")));
        mvc.perform(get("/admin/orders").session(s).param("day", "all"))
                .andExpect(content().string(containsString(old.getNumber())))
                .andExpect(content().string(containsString(mine.getNumber())));
    }

    @Test
    void отгрузкаОтмеченныхВозвращаетВТотЖеСписокСИтогом() throws Exception {
        World w = data.world("Отгрузка страницей");
        data.stockIn(w, 100);
        Order a = data.order(w, data.today().plusDays(1), PaymentMethod.CASH, 2, 1000);
        Order b = data.order(w, data.today().plusDays(1), PaymentMethod.CASH, 3, 1000);
        MockHttpSession s = login(w.operator());
        String back = "/admin/orders?agent=" + w.agent().getId() + "&exp=none";

        mvc.perform(get(back).session(s)).andExpect(content().string(containsString("Экспедитор…")))
                .andExpect(content().string(containsString(w.vehicle().getPlate())));
        // «Собран» — только новым
        mvc.perform(post("/admin/orders/assemble").with(csrf()).session(s).param("ids", a.getId().toString()).param("back", back))
                .andExpect(redirectedUrl(back));
        mvc.perform(get(back).session(s)).andExpect(content().string(containsString("Собрано: 1 заказ")));
        assertThat(jdbc.queryForObject("select status from orders where id = ?", String.class, a.getId())).isEqualTo("ASSEMBLED");

        // без даты не отгружается
        mvc.perform(post("/admin/orders/ship").with(csrf()).session(s).param("ids", a.getId().toString())
                .param("expeditor", w.expeditor().getId().toString()).param("back", back)).andExpect(redirectedUrl(back));
        mvc.perform(get(back).session(s)).andExpect(content().string(containsString("Выберите дату отгрузки")));

        LocalDate day = data.today().plusDays(2);
        mvc.perform(post("/admin/orders/ship").with(csrf()).session(s)
                        .param("ids", a.getId().toString(), b.getId().toString())
                        .param("expeditor", w.expeditor().getId().toString()).param("date", day.toString()).param("back", back))
                .andExpect(redirectedUrl(back));
        mvc.perform(get(back).session(s)).andExpect(content().string(containsString("Отгружено 2 заказа экспедитору " + w.expeditor().getName() + " на ")))
                .andExpect(content().string(not(containsString(a.getNumber()))));
        assertThat(jdbc.queryForList("select t.trip_date from trips t join trip_orders x on x.trip_id = t.id where x.order_id in (?, ?)",
                LocalDate.class, a.getId(), b.getId())).containsOnly(day);

        // чужой адрес возврата не принимается
        mvc.perform(post("/admin/orders/ship").with(csrf()).session(s).param("back", "https://example.com"))
                .andExpect(redirectedUrl("/admin/orders"));
    }

    @Test
    void накладныеПоМагазинамИОбщая() throws Exception {
        World w = data.world("Накладные");
        Outlet outlet2 = data.outletInNewRegion(w, w.agent());
        Order a = data.order(w, data.today().plusDays(1), PaymentMethod.CASH, 2, 1000);
        Order b = data.order(w, outlet2, w.agent(), data.today().plusDays(1), PaymentMethod.KASPI, 3, 500);
        Order foreign = data.order(data.world("Чужая"), data.today().plusDays(1), PaymentMethod.CASH, 1, 1000);
        MockHttpSession s = login(w.operator());

        mvc.perform(post("/admin/orders/invoices").with(csrf()).session(s).param("kind", "shop")
                        .param("ids", a.getId().toString(), b.getId().toString(), foreign.getId().toString()))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("Накладная № " + a.getNumber())))
                .andExpect(content().string(containsString("Накладная № " + b.getNumber())))
                .andExpect(content().string(containsString("Две тысячи тенге")))
                .andExpect(content().string(not(containsString(foreign.getNumber()))));

        mvc.perform(post("/admin/orders/invoices").with(csrf()).session(s).param("kind", "total")
                        .param("ids", a.getId().toString(), b.getId().toString()))
                .andExpect(content().string(containsString("Товарно-транспортная накладная")))
                .andExpect(content().string(containsString(w.product().getName())))
                .andExpect(content().string(containsString("Три тысячи пятьсот тенге")))
                .andExpect(content().string(containsString("Чистый возврат")))
                .andExpect(content().string(containsString("Испорченный возврат")))
                // второй части «кому сколько» больше нет
                .andExpect(content().string(not(containsString("Магазин, адрес"))));

        mvc.perform(get("/admin/orders/" + a.getId() + "/invoice").session(s))
                .andExpect(content().string(containsString("Накладная № " + a.getNumber())));
        mvc.perform(get("/admin/orders/" + foreign.getId() + "/invoice").session(s)).andExpect(status().isNotFound());
    }

    @Test
    void картаИЕёДанные() throws Exception {
        World w = data.world("Карта страницей");
        data.place(w.outlet(), 42.3, 69.58);
        MockHttpSession s = login(w.operator());
        mvc.perform(get("/admin/map").session(s)).andExpect(status().isOk())
                .andExpect(content().string(containsString("data-src=\"/admin/map/data\"")))
                .andExpect(content().string(containsString(w.agent().getName())));
        mvc.perform(get("/admin/map/data").session(s).param("date", data.today().toString()))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith("application/json"))
                .andExpect(content().string(containsString(w.outlet().getName())));

        // карта над списком заказов — с теми же условиями
        Employee agent2 = data.person(w, "Иван", Role.AGENT);
        Outlet outlet2 = data.outletInNewRegion(w, agent2);
        data.place(outlet2, 42.31, 69.6);
        Order mine = data.order(w, data.today().plusDays(1), PaymentMethod.CASH, 1, 1000);
        Order his = data.order(w, outlet2, agent2, data.today().plusDays(1), PaymentMethod.CASH, 1, 1000);
        mvc.perform(get("/admin/orders").session(s)).andExpect(content().string(containsString("data-src=\"/admin/orders/map-data\"")));
        mvc.perform(get("/admin/orders/map-data").session(s).param("agent", agent2.getId().toString()))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString(his.getNumber())))
                .andExpect(content().string(not(containsString(mine.getNumber()))));

        MockHttpSession keeper = login(data.person(w, "Кладовщик Карты", Role.STOREKEEPER));
        mvc.perform(get("/admin/map/data").session(keeper)).andExpect(redirectedUrl("/admin/dashboard"));
    }
}
