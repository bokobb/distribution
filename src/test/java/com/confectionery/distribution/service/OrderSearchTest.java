package com.confectionery.distribution.service;

import com.confectionery.distribution.TestData;
import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.TestcontainersConfiguration;
import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.OutletRepository;
import com.confectionery.distribution.tenant.TenantContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** Список заказов: фильтры по дате, торговым, филиалам, экспедитору, статусу; страницы; только своя компания. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class OrderSearchTest {

    @Autowired
    TestData data;
    @Autowired
    OrderSearch search;
    @Autowired
    OutletRepository outlets;
    @Autowired
    TransactionTemplate tx;

    World a;
    Employee agent2;
    Outlet outlet2;
    Region region1, region2;
    @Autowired
    org.springframework.jdbc.core.JdbcTemplate jdbc;

    LocalDate today, tomorrow;
    Order o1, o2, o3, o4, foreign;

    @BeforeEach
    void setUp() {
        today = data.today();
        tomorrow = today.plusDays(1);
        a = data.world("Поиск");
        agent2 = data.person(a, "Валодя", Role.AGENT);
        outlet2 = data.outletInNewRegion(a, agent2);
        data.stockIn(a, 100);
        o1 = data.order(a, tomorrow, PaymentMethod.CASH, 2, 1000);                                  // агент 1, регион 1
        o2 = data.order(a, outlet2, agent2, tomorrow, PaymentMethod.CASH, 3, 1000);                // агент 2, регион 2
        o3 = data.order(a, today, PaymentMethod.CASH, 1, 500);                                       // заказан вчера
        daysAgo(1, o3);
        o4 = data.order(a, outlet2, agent2, tomorrow, PaymentMethod.CASH, 4, 1000);
        data.trip(a, TripStatus.LOADING, o4);                                                        // уже у экспедитора
        foreign = data.order(data.world("Чужая"), tomorrow, PaymentMethod.CASH, 9, 9000);
        region1 = a.region();
        region2 = as(() -> outlets.findById(outlet2.getId()).orElseThrow().getRegion());
    }

    /** Дата заказа — столько дней назад (список ищет по дню, когда заказ пришёл). */
    private void daysAgo(int days, Order... list) {
        for (Order o : list)
            jdbc.update("update orders set created_at = created_at - make_interval(days => ?) where id = ?", days, o.getId());
    }

    private <T> T as(java.util.function.Supplier<T> action) {
        return TenantContext.call(a.id(), () -> tx.execute(s -> action.get()));
    }

    private static OrderSearch.Filter filter(LocalDate from, LocalDate to, List<Long> agents, List<Long> regions,
                                             Long exp, OrderStatus status, String q) {
        return new OrderSearch.Filter(from, to, agents, regions, exp, status, q);
    }

    private List<Long> ids(OrderSearch.Filter f) {
        return as(() -> search.find(f, 1, 50).rows().stream().map(Order::getId).toList());
    }

    @Test
    void безУсловийВсеЗаказыСвоейКомпанииСуммаИСтатусы() {
        OrderSearch.Page p = as(() -> search.find(filter(null, null, null, null, null, null, null), 1, 50));
        assertThat(p.rows()).extracting(Order::getId).containsExactlyInAnyOrder(o1.getId(), o2.getId(), o3.getId(), o4.getId());
        assertThat(p.total()).isEqualTo(4);
        assertThat(p.sum()).isEqualTo(2000 + 3000 + 500 + 4000);
        assertThat(p.counts()).containsEntry(OrderStatus.ACCEPTED, 3L).containsEntry(OrderStatus.IN_TRIP, 1L);
        assertThat(p.rows()).extracting(Order::getId).doesNotContain(foreign.getId());
    }

    @Test
    void поДатеЗаказаТорговымИФилиалам() {
        assertThat(ids(filter(today, today, null, null, null, null, null))).containsExactlyInAnyOrder(o1.getId(), o2.getId(), o4.getId());
        assertThat(ids(filter(today.minusDays(1), today.minusDays(1), null, null, null, null, null))).containsExactly(o3.getId());
        assertThat(ids(filter(tomorrow, null, null, null, null, null, null))).isEmpty();
        assertThat(ids(filter(today, null, List.of(agent2.getId()), null, null, null, null))).containsExactlyInAnyOrder(o2.getId(), o4.getId());
        assertThat(ids(filter(null, null, List.of(a.agent().getId(), agent2.getId()), null, null, null, null))).hasSize(4);
        assertThat(ids(filter(null, null, null, List.of(region2.getId()), null, null, null))).containsExactlyInAnyOrder(o2.getId(), o4.getId());
        assertThat(ids(filter(null, null, null, List.of(region1.getId()), null, null, null))).containsExactlyInAnyOrder(o1.getId(), o3.getId());
        assertThat(ids(filter(null, null, List.of(a.agent().getId()), List.of(region2.getId()), null, null, null))).isEmpty();
    }

    @Test
    void поЭкспедиторуСтатусуИПоиску() {
        assertThat(ids(filter(null, null, null, null, OrderSearch.NO_EXPEDITOR, null, null))).containsExactlyInAnyOrder(o1.getId(), o2.getId(), o3.getId());
        assertThat(ids(filter(null, null, null, null, a.expeditor().getId(), null, null))).containsExactly(o4.getId());
        assertThat(ids(filter(null, null, null, null, null, OrderStatus.IN_TRIP, null))).containsExactly(o4.getId());
        assertThat(ids(filter(null, null, null, null, null, null, o2.getNumber().toLowerCase()))).containsExactly(o2.getId());
        assertThat(ids(filter(null, null, null, null, null, null, "валод"))).containsExactlyInAnyOrder(o2.getId(), o4.getId());

        // статус сужает строки, но разбивка по статусам — по остальным условиям
        OrderSearch.Page p = as(() -> search.find(filter(null, null, null, null, null, OrderStatus.IN_TRIP, null), 1, 50));
        assertThat(p.counts()).containsEntry(OrderStatus.ACCEPTED, 3L);
    }

    @Test
    void страницы() {
        for (int i = 0; i < 27; i++) daysAgo(5, data.order(a, today, PaymentMethod.KASPI, 1, 100));
        OrderSearch.Filter f = filter(today.minusDays(5), today.minusDays(5), null, null, null, null, null);
        OrderSearch.Page first = as(() -> search.find(f, 1, 25));
        assertThat(first.rows()).hasSize(25);
        assertThat(first.pages()).isEqualTo(2);
        assertThat(first.sum()).isEqualTo(2700);
        OrderSearch.Page last = as(() -> search.find(f, 99, 25)); // за последней — последняя
        assertThat(last.page()).isEqualTo(2);
        assertThat(last.rows()).hasSize(2);
        assertThat(last.first()).isEqualTo(26);
        assertThat(last.last()).isEqualTo(27);
        assertThat(as(() -> search.find(f, 1, 7)).size()).isEqualTo(OrderSearch.DEFAULT_SIZE); // чужой размер — по умолчанию

        assertThat(new OrderSearch.Page(List.of(), 500, 0, java.util.Map.of(), 10, 25).around())
                .containsExactly(1, 0, 8, 9, 10, 11, 12, 0, 20);
    }
}
