package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.PaymentMethod;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.domain.Role;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.time.LocalDate;

import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Данные агента для работы без сети: только его маршруты и магазины своей компании, цены на сегодня, долги. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class AgentDataTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private ResultActions agentData(Employee e) throws Exception {
        return mvc.perform(get("/api/mobile/agent/data").header("Authorization", "Bearer " + data.jwt(e)));
    }

    @Test
    void агентПолучаетСвоиМаршрутыМагазиныЦеныИДолги() throws Exception {
        World w = data.world("Агент");
        World other = data.world("Чужая");
        data.price(w, PriceKind.WHOLESALE, 450, data.today().minusDays(10));
        data.price(w, PriceKind.WHOLESALE, 500, data.today());
        data.price(w, PriceKind.WHOLESALE, 550, data.today().plusDays(1));
        data.price(w, PriceKind.RETAIL, 600, data.today().minusDays(1));
        data.openingDebt(w, 30_000, data.today().minusDays(30));
        // магазин другого агента той же компании и выключенный товар агенту не нужны
        Outlet foreign = data.outletInNewRegion(w, data.person(w, "Другой агент", Role.AGENT));
        jdbc.update("insert into products (company_id, name, category, active) values (?, 'Снят с продажи', 'Печенье', false)", w.id());

        agentData(w.agent()).andExpect(status().isOk())
                .andExpect(jsonPath("$.date").value(data.today().toString()))
                .andExpect(jsonPath("$.settings.visitRadius").value(200))
                .andExpect(jsonPath("$.settings.gpsInterval").value(5))
                .andExpect(jsonPath("$.routes", hasSize(1)))
                .andExpect(jsonPath("$.routes[0].name").value(w.route().getName()))
                .andExpect(jsonPath("$.routes[0].days", contains(1, 2, 3, 4, 5, 6, 7)))
                .andExpect(jsonPath("$.routes[0].outlets", contains(w.outlet().getId().intValue())))
                .andExpect(jsonPath("$.outlets", hasSize(1)))
                .andExpect(jsonPath("$.outlets[0].name").value(w.outlet().getName()))
                .andExpect(jsonPath("$.outlets[0].priceKind").value("WHOLESALE"))
                .andExpect(jsonPath("$.outlets[0].debt").value(30_000))
                .andExpect(jsonPath("$.outlets[0].overdue").value(30_000))
                .andExpect(jsonPath("$.products", hasSize(1)))
                .andExpect(jsonPath("$.products[0].wholesale").value(500))
                .andExpect(jsonPath("$.products[0].retail").value(600));

        jdbc.update("update outlets set status = 'CLOSED' where id = ?", w.outlet().getId());
        agentData(w.agent()).andExpect(jsonPath("$.routes[0].outlets", hasSize(0))).andExpect(jsonPath("$.outlets", hasSize(0)));
        agentData(other.agent()).andExpect(jsonPath("$.outlets[0].name").value(other.outlet().getName()))
                .andExpect(jsonPath("$.outlets", hasSize(1)));
        agentData(w.agent()).andExpect(jsonPath("$.outlets[?(@.id == " + foreign.getId() + ")]", hasSize(0)));
    }

    @Test
    void остальныеМагазиныКомпанииБезДолговИТелефонов() throws Exception {
        World w = data.world("Карта");
        World other = data.world("Карта чужой компании");
        data.place(w.outlet(), 42.30, 69.60);
        data.place(other.outlet(), 42.31, 69.61);
        Outlet near = data.outletInNewRegion(w, data.person(w, "Сосед", Role.AGENT));
        data.place(near, 42.32, 69.62);
        Outlet noPoint = data.outletInNewRegion(w, data.person(w, "Без точки", Role.AGENT));
        String region = jdbc.queryForObject("select g.name from regions g join routes r on r.region_id = g.id "
                + "join route_outlets ro on ro.route_id = r.id where ro.outlet_id = ?", String.class, near.getId());

        String nearAt = "$.others[?(@.id == " + near.getId() + ")]";
        // заказ принимают в любом магазине компании: у чужих — прайс и владелец, без долгов и телефонов
        agentData(w.agent()).andExpect(status().isOk())
                .andExpect(jsonPath("$.others", hasSize(2)))
                .andExpect(jsonPath(nearAt + ".name").value(near.getName()))
                .andExpect(jsonPath(nearAt + ".lat").value(42.32))
                .andExpect(jsonPath(nearAt + ".region").value(region))
                .andExpect(jsonPath(nearAt + ".priceKind").value("WHOLESALE"))
                .andExpect(jsonPath(nearAt + ".status").value("ACTIVE"))
                .andExpect(jsonPath("$.others[0].debt").doesNotExist())
                .andExpect(jsonPath("$.others[0].phone").doesNotExist())
                .andExpect(jsonPath("$.others[?(@.id == " + noPoint.getId() + ")].lat", contains((Object) null)))
                .andExpect(jsonPath("$.others[?(@.id == " + w.outlet().getId() + ")]", empty()))
                .andExpect(jsonPath("$.others[?(@.id == " + other.outlet().getId() + ")]", empty()));

        jdbc.update("update outlets set status = 'CLOSED' where id in (?, ?)", near.getId(), noPoint.getId());
        agentData(w.agent()).andExpect(jsonPath("$.others", empty()));
    }

    @Test
    void заказыПрошлогоРабочегоДня_иКогдаДоставлены() throws Exception {
        World w = data.world("Вчерашние заказы");
        Order early = data.order(w, data.today(), PaymentMethod.CASH, 10, 100);
        Order delivered = data.order(w, data.today(), PaymentMethod.KASPI, 5, 100);
        Order waiting = data.order(w, data.today(), PaymentMethod.CASH, 3, 100);
        Order today = data.order(w, data.today().plusDays(1), PaymentMethod.CASH, 1, 100);
        // у другого агента вчера был заказ — прошлый день считается по своим
        Order foreign = data.order(w, w.outlet(), data.person(w, "Сосед по складу", Role.AGENT), data.today(), PaymentMethod.CASH, 1, 100);
        LocalDate previous = data.today().minusDays(3);
        jdbc.update("update orders set created_at = ? where id = ?", data.today().minusDays(10).atTime(9, 0), early.getId());
        jdbc.update("update orders set created_at = ? where id in (?, ?)", previous.atTime(11, 0), delivered.getId(), waiting.getId());
        jdbc.update("update orders set created_at = ? where id = ?", data.today().minusDays(1).atTime(12, 0), foreign.getId());
        data.delivered(w, delivered, null, 5, data.today().minusDays(2).atTime(10, 15));

        String at = "$.previousOrders[?(@.uuid == '%s')]";
        agentData(w.agent()).andExpect(status().isOk())
                .andExpect(jsonPath("$.orders", hasSize(1)))
                .andExpect(jsonPath("$.orders[0].uuid").value(today.getUuid().toString()))
                .andExpect(jsonPath("$.orders[0].deliveredAt").doesNotExist())
                .andExpect(jsonPath("$.previousDate").value(previous.toString()))
                .andExpect(jsonPath("$.previousOrders", hasSize(2)))
                .andExpect(jsonPath(at.formatted(delivered.getUuid()) + ".deliveredAt")
                        .value(data.today().minusDays(2).atTime(10, 15).toString() + ":00"))
                .andExpect(jsonPath(at.formatted(delivered.getUuid()) + ".status").value("DELIVERED"))
                .andExpect(jsonPath(at.formatted(waiting.getUuid()) + ".deliveredAt", contains((Object) null)));

        // две недели без заказов — вкладки «Вчера» нет
        World fresh = data.world("Без прошлых заказов");
        agentData(fresh.agent()).andExpect(jsonPath("$.previousDate").doesNotExist())
                .andExpect(jsonPath("$.previousOrders", empty()));
    }

    @Test
    void экспедиторуДанныеАгентаЗакрыты() throws Exception {
        World w = data.world("Экспедитор");
        agentData(w.expeditor()).andExpect(status().isForbidden());
    }
}
