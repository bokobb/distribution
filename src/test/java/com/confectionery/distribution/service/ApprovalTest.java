package com.confectionery.distribution.service;

import com.confectionery.distribution.TestData;
import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.TestcontainersConfiguration;
import com.confectionery.distribution.domain.ApprovalKind;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.PaymentMethod;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import com.confectionery.distribution.tenant.TenantContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** «Разрешения»: заказ закрыт по просрочке, кто его открывает, сверх лимита — «только оплата при доставке»,
 * «Вернуть», недоплата при выдаче. */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestData.class})
class ApprovalTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    TestData data;
    @Autowired
    JdbcTemplate jdbc;
    @Autowired
    ApprovalService approvals;
    @Autowired
    TransactionTemplate tx;

    private <T> T in(World w, Supplier<T> action) {
        return TenantContext.call(w.id(), () -> tx.execute(s -> action.get()));
    }

    private ResultActions order(World w, UUID uuid, String payment, int qty) throws Exception {
        LocalDateTime at = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(5);
        return mvc.perform(post("/api/mobile/agent/orders").header("Authorization", "Bearer " + data.jwt(w.agent()))
                .contentType(MediaType.APPLICATION_JSON).content("""
                        {"uuid": "%s", "outletId": %d, "createdAt": "%s", "payment": "%s",
                         "items": [{"productId": %d, "qty": %d}]}""".formatted(uuid, w.outlet().getId(), at, payment,
                        w.product().getId(), qty)));
    }

    private static Actor actor(World w, Role role) {
        return Actor.system(role.getLabel() + " " + w.company().getName());
    }

    private String state(UUID uuid) {
        return jdbc.queryForObject("select status || ' ' || coalesce(hold, '-') || ' ' || payment_method from orders where uuid = ?",
                String.class, uuid);
    }

    @Test
    void просрочка_заказЗакрыт_открываетДиректор_вернуть() throws Exception {
        World w = data.world("Просрочка");
        data.price(w, PriceKind.WHOLESALE, 1000, data.today().minusDays(60));
        data.openingDebt(w, 40_000, data.today().minusDays(30)); // отсрочка 7 дней — просрочено 23 дня
        UUID uuid = UUID.randomUUID();

        order(w, uuid, "CASH", 5).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("NEEDS_APPROVAL"))
                .andExpect(jsonPath("$.note").value("Заказ закрыт: просрочка — ждёт разрешения директора"));
        assertThat(state(uuid)).isEqualTo("NEEDS_APPROVAL OVERDUE CASH");
        String key = "o" + data.orderByUuid(uuid).getId();

        ApprovalService.Page page = in(w, () -> approvals.page(w.id(), Role.OPERATOR));
        ApprovalService.Item item = page.items().stream().filter(i -> i.key().equals(key)).findFirst().orElseThrow();
        assertThat(item.kind()).isEqualTo(ApprovalKind.OVERDUE);
        assertThat(item.terms().get(0).value()).isEqualTo("40 000 ₸");
        assertThat(item.terms().get(1).value()).isEqualTo("23");
        assertThat(item.acts().get(0).allowed()).isFalse();
        assertThat(item.hint()).isEqualTo("Один заказ открывает директор и владелец");

        Actor op = actor(w, Role.OPERATOR);
        assertThatThrownBy(() -> in(w, () -> approvals.decide(key, "OK", op, Role.OPERATOR)))
                .isInstanceOf(FormException.class).hasMessage("Один заказ при просрочке открывает директор и владелец");
        assertThat(state(uuid)).isEqualTo("NEEDS_APPROVAL OVERDUE CASH");

        Actor dir = actor(w, Role.DIRECTOR);
        assertThat(in(w, () -> approvals.decide(key, "OK", dir, Role.DIRECTOR))).contains("Разрешён один заказ");
        assertThat(state(uuid)).startsWith("ACCEPTED");
        ApprovalService.Page after = in(w, () -> approvals.page(w.id(), Role.DIRECTOR));
        assertThat(after.items()).noneMatch(i -> i.key().equals(key));
        assertThat(after.today()).hasSize(1);
        assertThatThrownBy(() -> in(w, () -> approvals.decide(key, "DENY", dir, Role.DIRECTOR)))
                .isInstanceOf(FormException.class).hasMessageContaining("решать не нужно");

        in(w, () -> approvals.undo(after.today().get(0).id(), dir));
        assertThat(state(uuid)).isEqualTo("NEEDS_APPROVAL OVERDUE CASH");
        assertThat(in(w, () -> approvals.page(w.id(), Role.DIRECTOR)).today()).isEmpty();
    }

    @Test
    void сверхЛимита_толькоОплатаПриДоставке_вернутьВДолг() throws Exception {
        World w = data.world("Сверх лимита");
        data.price(w, PriceKind.WHOLESALE, 1000, data.today().minusDays(1));
        data.openingDebt(w, 95_000, data.today().minusDays(2));
        UUID uuid = UUID.randomUUID();
        order(w, uuid, "CREDIT", 10).andExpect(jsonPath("$.status").value("NEEDS_APPROVAL"));
        assertThat(state(uuid)).isEqualTo("NEEDS_APPROVAL LIMIT CREDIT");
        String key = "o" + data.orderByUuid(uuid).getId();

        ApprovalService.Item item = in(w, () -> approvals.page(w.id(), Role.OPERATOR)).items().stream()
                .filter(i -> i.key().equals(key)).findFirst().orElseThrow();
        assertThat(item.terms()).extracting(ApprovalService.Term::value)
                .containsExactly("95 000 ₸", "0 ₸", "10 000 ₸", "105 000 ₸");
        assertThat(item.note()).isEqualTo("лимит 100 000 ₸ · сверх на 5 000 ₸");

        Actor op = actor(w, Role.OPERATOR);
        in(w, () -> approvals.decide(key, "CASH", op, Role.OPERATOR));
        assertThat(state(uuid)).isEqualTo("ACCEPTED LIMIT CASH");
        Long done = in(w, () -> approvals.page(w.id(), Role.OPERATOR)).today().get(0).id();
        in(w, () -> approvals.undo(done, op));
        assertThat(state(uuid)).isEqualTo("NEEDS_APPROVAL LIMIT CREDIT");

        in(w, () -> approvals.decide(key, "DENY", op, Role.OPERATOR));
        assertThat(state(uuid)).isEqualTo("CANCELLED LIMIT CREDIT");
    }

    @Test
    void недоплатаСверхЛимита_наРазрешение_записатьВДолг() throws Exception {
        World w = data.world("Недоплата");
        data.stockIn(w, 100);
        data.openingDebt(w, 95_000, data.today().minusDays(2));
        Order o = data.order(w, data.today(), PaymentMethod.CASH, 10, 1_000);
        Trip t = data.trip(w, TripStatus.ON_ROAD, o);
        LocalDateTime at = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS).minusMinutes(5);
        mvc.perform(post("/api/mobile/expeditor/deliveries").header("Authorization", "Bearer " + data.jwt(w.expeditor()))
                .contentType(MediaType.APPLICATION_JSON).content("""
                        {"uuid": "%s", "orderId": %d, "deliveredAt": "%s", "refused": false, "items": [],
                         "payments": [{"uuid": "%s", "method": "CASH", "amount": 2000}]}"""
                        .formatted(UUID.randomUUID(), o.getId(), at, UUID.randomUUID())))
                .andExpect(status().isOk()).andExpect(jsonPath("$.paid").value(2000));

        ApprovalService.Item item = in(w, () -> approvals.page(w.id(), Role.OPERATOR)).items().stream()
                .filter(i -> i.kind() == ApprovalKind.UNDERPAY).findFirst().orElseThrow();
        assertThat(item.title()).isEqualTo("Заказ " + o.getNumber() + " · 10 000 ₸ · рейс " + t.getNumber());
        assertThat(item.terms()).extracting(ApprovalService.Term::value)
                .containsExactly("10 000 ₸", "2 000 ₸", "8 000 ₸", "103 000 ₸");
        assertThat(item.note()).isEqualTo("лимит 100 000 ₸ · сверх на 3 000 ₸");
        assertThat(jdbc.queryForObject("select count(*) from approvals where company_id = ? and decision is null", Integer.class, w.id()))
                .isEqualTo(1);

        Actor op = actor(w, Role.OPERATOR);
        assertThat(in(w, () -> approvals.decide(item.key(), "OK", op, Role.OPERATOR))).endsWith("Недоплата 8 000 ₸ — в долг магазина");
        assertThat(in(w, () -> approvals.page(w.id(), Role.OPERATOR)).items()).noneMatch(i -> i.kind() == ApprovalKind.UNDERPAY);
        assertThatThrownBy(() -> in(w, () -> approvals.decide(item.key(), "TASK", op, Role.OPERATOR)))
                .isInstanceOf(FormException.class).hasMessageStartingWith("Уже решено");
        assertThat(jdbc.queryForObject("select count(*) from order_events where order_id = ? and message like 'Недоплата 8 000%'",
                Integer.class, o.getId())).isEqualTo(3); // выдача, на разрешение, решение
    }
}
