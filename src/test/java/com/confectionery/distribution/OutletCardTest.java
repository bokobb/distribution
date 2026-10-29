package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.PaymentMethod;
import com.confectionery.distribution.domain.ProductReturn;
import com.confectionery.distribution.domain.Visit;
import com.confectionery.distribution.domain.VisitResult;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Карточка магазина у торгового: что берёт, доля возвратов, что перестал брать, история; сводка для карты. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class OutletCardTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;

    private Order order(World w, int daysAgo, Long roll) {
        Order o = data.order(w, data.today(), PaymentMethod.CASH, 10, 100);
        jdbc.update("update orders set created_at = ? where id = ?", data.today().minusDays(daysAgo).atTime(10, 0), o.getId());
        if (roll != null)
            jdbc.update("insert into order_items (company_id, order_id, product_id, qty, price) values (?, ?, ?, 5, 200)",
                    w.id(), o.getId(), roll);
        return o;
    }

    @Test
    void чтоБерёт_перестал_возвраты_история_иСводкаДляКарты() throws Exception {
        World w = data.world("Карточка");
        Long roll = jdbc.queryForObject("insert into products (company_id, name, category, active) "
                + "values (?, 'Рулет с маком', 'Рулеты', true) returning id", Long.class, w.id());
        order(w, 40, roll);
        order(w, 30, roll);
        Order last = order(w, 3, null);
        jdbc.update("update order_items set qty = 20 where order_id = ?", last.getId());
        Order cancelled = order(w, 1, null);
        jdbc.update("update orders set status = 'CANCELLED' where id = ?", cancelled.getId());
        ProductReturn back = data.productReturn(w, null, 3, 100, data.today().minusDays(2));
        jdbc.update("update returns set order_id = ? where id = ?", last.getId(), back.getId());
        Visit visit = data.visit(w, w.outlet(), data.today().minusDays(5).atTime(11, 0), VisitResult.NO_ORDER, null, null);
        jdbc.update("update visits set refuse_reason = 'Товар ещё есть' where id = ?", visit.getId());
        String jwt = data.jwt(w.agent());

        mvc.perform(get("/api/mobile/agent/outlets/{id}/card", w.outlet().getId()).header("Authorization", "Bearer " + jwt))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.createdOn").value(data.today().toString()))
                .andExpect(jsonPath("$.avgOrder").value(2000))
                .andExpect(jsonPath("$.orders8w").value(3))
                .andExpect(jsonPath("$.ordered").value(6000))
                .andExpect(jsonPath("$.returned").value(300))
                .andExpect(jsonPath("$.returnReason").value("DEFECT"))
                .andExpect(jsonPath("$.stopped").value("Рулет с маком"))
                .andExpect(jsonPath("$.stoppedSince").value(data.today().minusDays(30).toString()))
                .andExpect(jsonPath("$.history", hasSize(5)))
                .andExpect(jsonPath("$.history[0].statusLabel").value("Отменён"))
                .andExpect(jsonPath("$.history[1].orderTotal").value(2000))
                .andExpect(jsonPath("$.history[1].returnTotal").value(300))
                .andExpect(jsonPath("$.history[1].returnReason").value("DEFECT"))
                .andExpect(jsonPath("$.history[2].kind").value("NO_ORDER"))
                .andExpect(jsonPath("$.history[2].reason").value("Товар ещё есть"))
                .andExpect(jsonPath("$.history[3].returnTotal").value(0));

        String stat = "$.stats[?(@.outletId == " + w.outlet().getId() + ")]";
        mvc.perform(get("/api/mobile/agent/data").header("Authorization", "Bearer " + jwt))
                .andExpect(jsonPath(stat + ".lastVisit").value(data.today().minusDays(5).toString()))
                .andExpect(jsonPath(stat + ".avgOrder").value(2000));

        // магазин другой компании — не найден
        World other = data.world("Чужая карточка");
        mvc.perform(get("/api/mobile/agent/outlets/{id}/card", other.outlet().getId()).header("Authorization", "Bearer " + jwt))
                .andExpect(status().isNotFound());
    }

    @Test
    void новыйМагазин_безИстории() throws Exception {
        World w = data.world("Пустая карточка");
        mvc.perform(get("/api/mobile/agent/outlets/{id}/card", w.outlet().getId()).header("Authorization", "Bearer " + data.jwt(w.agent())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.avgOrder").value(0))
                .andExpect(jsonPath("$.orders8w").value(0))
                .andExpect(jsonPath("$.stopped").doesNotExist())
                .andExpect(jsonPath("$.history", hasSize(0)));
    }
}
