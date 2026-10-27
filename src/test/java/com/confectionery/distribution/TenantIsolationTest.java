package com.confectionery.distribution;

import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.OrderRepository;
import com.confectionery.distribution.repository.OutletRepository;
import com.confectionery.distribution.repository.RegionRepository;
import com.confectionery.distribution.service.*;
import com.confectionery.distribution.tenant.TenantContext;
import org.hibernate.PropertyValueException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.Optional;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Пользователь компании А не видит данных компании Б — ни списками, ни по id, ни через сервисы. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class TenantIsolationTest {

    @Autowired
    TestData data;
    @Autowired
    OutletRepository outletRepo;
    @Autowired
    OrderRepository orderRepo;
    @Autowired
    RegionRepository regionRepo;
    @Autowired
    OutletService outlets;
    @Autowired
    OrderService orders;
    @Autowired
    TripService trips;
    @Autowired
    StaffService staff;
    @Autowired
    StockService stock;
    @Autowired
    DashboardService dashboard;
    @Autowired
    TransactionTemplate tx;

    World a, b;
    Order orderA, orderB;
    Trip tripB;

    @BeforeEach
    void setUp() {
        a = data.world("А");
        b = data.world("Б");
        data.stockIn(a, 100);
        data.stockIn(b, 100);
        orderA = data.order(a, data.today().plusDays(1), PaymentMethod.CASH, 5, 1000);
        orderB = data.order(b, data.today().plusDays(1), PaymentMethod.CASH, 7, 1000);
        tripB = data.trip(b, TripStatus.ON_ROAD, data.order(b, data.today(), PaymentMethod.CASH, 3, 1000));
    }

    private <T> T as(World w, Supplier<T> action) {
        return TenantContext.call(w.id(), () -> tx.execute(s -> action.get()));
    }

    @Test
    void спискиТолькоСвоейКомпании() {
        as(a, () -> {
            assertThat(outlets.list(null)).extracting(Outlet::getId).containsExactly(a.outlet().getId());
            assertThat(orderRepo.findAll()).extracting(Order::getCompanyId).containsOnly(a.id());
            assertThat(orders.byDay("all")).extracting(Order::getId).containsExactly(orderA.getId());
            assertThat(trips.current(null)).isEmpty();
            assertThat(staff.employees(null)).extracting(Employee::getCompanyId).containsOnly(a.id());
            assertThat(stock.rows(null)).extracting(r -> r.product().getId()).containsExactly(a.product().getId());
            assertThat(dashboard.snapshot().summary(null).tomorrowOrders()).isEqualTo(1);
            return null;
        });
    }

    @Test
    void чужаяЗаписьПоIdНеНаходится() {
        as(a, () -> {
            assertThat(outletRepo.findById(b.outlet().getId())).isEmpty();
            assertThat(orderRepo.findById(orderB.getId())).isEmpty();
            assertThatThrownBy(() -> outlets.get(b.outlet().getId())).isInstanceOf(NotFoundException.class);
            assertThatThrownBy(() -> orders.get(orderB.getId())).isInstanceOf(NotFoundException.class);
            assertThatThrownBy(() -> trips.get(tripB.getId())).isInstanceOf(NotFoundException.class);
            return null;
        });
    }

    @Test
    void действиеНадЧужимЗаказомНевозможно() {
        TenantContext.run(a.id(), () -> assertThatThrownBy(() -> orders.cancel(orderB.getId(), Actor.system("Тест"), "проверка"))
                .isInstanceOf(NotFoundException.class));
        assertThat(as(b, () -> orderRepo.findById(orderB.getId()).orElseThrow().getStatus())).isEqualTo(OrderStatus.ACCEPTED);
    }

    @Test
    void записатьВЧужуюКомпаниюНельзя() {
        assertThatThrownBy(() -> as(a, () -> {
            Region r = new Region().setName("Чужой регион");
            r.setCompany(b.company());
            return regionRepo.save(r);
        })).hasRootCauseInstanceOf(PropertyValueException.class);
    }

    @Test
    void новаяЗаписьПолучаетКомпаниюСама() {
        Region r = as(a, () -> regionRepo.save(new Region().setName("Свой регион")));
        assertThat(r.getCompanyId()).isEqualTo(a.id());
    }

    @Test
    void безКомпанииНеВидноНичего() {
        TenantContext.clear();
        List<Outlet> all = tx.execute(s -> outletRepo.findAll());
        Optional<Outlet> one = tx.execute(s -> outletRepo.findById(a.outlet().getId()));
        assertThat(all).isEmpty();
        assertThat(one).isEmpty();
    }

    @Test
    void владелецВоВсехКомпанияхВидитВсе() {
        var ids = TenantContext.asRoot(() -> tx.execute(s -> outletRepo.findAll().stream().map(Outlet::getId).toList()));
        assertThat(ids).contains(a.outlet().getId(), b.outlet().getId());
    }
}
