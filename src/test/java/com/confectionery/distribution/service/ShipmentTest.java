package com.confectionery.distribution.service;

import com.confectionery.distribution.TestData;
import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.TestcontainersConfiguration;
import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.tenant.TenantContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** «Отгрузить экспедитору» из списка заказов: рейс на день доставки, товар в машину, что не ушло — с причиной. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class ShipmentTest {

    @Autowired
    TestData data;
    @Autowired
    TripService trips;
    @Autowired
    JdbcTemplate jdbc;

    World w;
    LocalDate tomorrow;
    Actor actor;

    @BeforeEach
    void setUp() {
        w = data.world("Отгрузка");
        tomorrow = data.today().plusDays(1);
        actor = new Actor(w.operator(), "Оператор (оператор)");
    }

    private TripService.Shipment ship(World as, Long expeditorId, Order... list) {
        List<Long> ids = java.util.Arrays.stream(list).map(Order::getId).toList();
        return TenantContext.call(as.id(), () -> trips.ship(ids, expeditorId, actor));
    }

    private String status(Order o) {
        return jdbc.queryForObject("select status from orders where id = ?", String.class, o.getId());
    }

    private void setStatus(Order o, OrderStatus s) {
        jdbc.update("update orders set status = ? where id = ?", s.name(), o.getId());
    }

    @Test
    void принятыеИСобранныеУходятВРейсНаДеньДоставкиОстальныеСПричиной() {
        data.stockIn(w, 100);
        Order a = data.order(w, tomorrow, PaymentMethod.CASH, 10, 500);
        Order b = data.order(w, tomorrow, PaymentMethod.CASH, 5, 500);
        setStatus(b, OrderStatus.ASSEMBLED);
        Order wait = data.order(w, tomorrow, PaymentMethod.CREDIT, 3, 500);
        setStatus(wait, OrderStatus.NEEDS_APPROVAL);
        Order cancelled = data.order(w, tomorrow, PaymentMethod.CASH, 3, 500);
        setStatus(cancelled, OrderStatus.CANCELLED);

        TripService.Shipment s = ship(w, w.expeditor().getId(), a, b, wait, cancelled);

        assertThat(s.shipped()).isEqualTo(2);
        assertThat(s.trips()).hasSize(1);
        Trip t = s.trips().get(0);
        assertThat(t.getDate()).isEqualTo(tomorrow);
        assertThat(t.getStatus()).isEqualTo(TripStatus.ON_ROAD); // кнопки «В путь» нет
        assertThat(t.getStartedAt()).isNotNull();
        assertThat(t.getNumber()).startsWith("Р-");
        assertThat(s.skipped()).containsEntry("ждут разрешения (долг сверх лимита)", List.of(wait.getNumber()))
                .containsEntry("отменены", List.of(cancelled.getNumber()));
        assertThat(status(a)).isEqualTo("IN_TRIP");
        assertThat(status(b)).isEqualTo("IN_TRIP");
        assertThat(status(wait)).isEqualTo("NEEDS_APPROVAL");
        assertThat(data.balance(w.main(), w.product())).isEqualTo(85);
        assertThat(data.balance(w.car(), w.product())).isEqualTo(15);
        assertThat(jdbc.queryForObject("select trip_id from trip_orders where order_id = ?", Long.class, a.getId())).isEqualTo(t.getId());
        assertThat(jdbc.queryForObject("select count(*) from order_events where order_id = ? and message like 'Отгрузил экспедитору%'",
                Integer.class, a.getId())).isEqualTo(1);

        // повторная отгрузка тех же — «уже в рейсе», товар не двигается
        TripService.Shipment again = ship(w, w.expeditor().getId(), a);
        assertThat(again.shipped()).isZero();
        assertThat(again.skipped()).containsEntry("уже в рейсе", List.of(a.getNumber()));
        assertThat(data.balance(w.main(), w.product())).isEqualTo(85);
    }

    @Test
    void загружаемыйРейсДополняетсяДругойДеньДругойРейс() {
        data.stockIn(w, 100);
        Order first = data.order(w, tomorrow, PaymentMethod.CASH, 1, 100);
        Order second = data.order(w, tomorrow, PaymentMethod.CASH, 1, 100);
        Order later = data.order(w, tomorrow.plusDays(1), PaymentMethod.CASH, 1, 100);
        Trip t1 = ship(w, w.expeditor().getId(), first).trips().get(0);
        TripService.Shipment s = ship(w, w.expeditor().getId(), second, later);
        assertThat(s.trips()).hasSize(2);
        assertThat(s.trips().get(0).getId()).isEqualTo(t1.getId());
        assertThat(s.trips().get(1).getDate()).isEqualTo(tomorrow.plusDays(1));
        assertThat(jdbc.queryForList("select position from trip_orders where trip_id = ? order by position", Integer.class, t1.getId()))
                .containsExactly(0, 1);

        // касса принята — рейс закрыт, следующая отгрузка на тот же день — новый рейс
        jdbc.update("update trips set status = 'CLOSED' where id = ?", t1.getId());
        Order afterClose = data.order(w, tomorrow, PaymentMethod.CASH, 1, 100);
        Trip t3 = ship(w, w.expeditor().getId(), afterClose).trips().get(0);
        assertThat(t3.getId()).isNotEqualTo(t1.getId());
        assertThat(t3.getDate()).isEqualTo(tomorrow);
    }

    @Test
    void неХватаетТовара_ничегоНеОтгружено() {
        data.stockIn(w, 12);
        Order a = data.order(w, tomorrow, PaymentMethod.CASH, 10, 100);
        Order b = data.order(w, tomorrow, PaymentMethod.CASH, 5, 100);
        assertThatThrownBy(() -> ship(w, w.expeditor().getId(), a, b))
                .isInstanceOf(FormException.class).hasMessageContaining("есть 12, нужно 15");
        assertThat(status(a)).isEqualTo("ACCEPTED");
        assertThat(status(b)).isEqualTo("ACCEPTED");
        assertThat(data.balance(w.main(), w.product())).isEqualTo(12);
        assertThat(jdbc.queryForObject("select count(*) from trips where company_id = ?", Integer.class, w.id())).isZero();
    }

    @Test
    void безМашиныИБезЭкспедитораНельзя() {
        data.stockIn(w, 10);
        Order a = data.order(w, tomorrow, PaymentMethod.CASH, 1, 100);
        Employee noCar = data.person(w, "Геннадий", Role.EXPEDITOR);
        assertThatThrownBy(() -> ship(w, noCar.getId(), a)).isInstanceOf(FormException.class).hasMessageContaining("не закреплена машина");
        assertThatThrownBy(() -> ship(w, null, a)).isInstanceOf(FormException.class).hasMessageContaining("Выберите экспедитора");
        assertThatThrownBy(() -> ship(w, w.agent().getId(), a)).isInstanceOf(FormException.class).hasMessageContaining("Выберите экспедитора");
        assertThat(status(a)).isEqualTo("ACCEPTED");
    }

    @Test
    void чужиеЗаказыИЧужойЭкспедиторНеДоступны() {
        World other = data.world("Чужая");
        data.stockIn(other, 10);
        Order foreign = data.order(other, tomorrow, PaymentMethod.CASH, 1, 100);
        assertThat(ship(w, w.expeditor().getId(), foreign).shipped()).isZero();
        assertThatThrownBy(() -> ship(w, other.expeditor().getId(), data.order(w, tomorrow, PaymentMethod.CASH, 1, 100)))
                .isInstanceOf(FormException.class);
        assertThat(status(foreign)).isEqualTo("ACCEPTED");
    }
}
