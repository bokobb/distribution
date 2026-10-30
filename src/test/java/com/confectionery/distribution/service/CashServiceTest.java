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
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDateTime;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Приём рейса вечером: недостача записывается на экспедитора, товар возвращается на склады. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class CashServiceTest {

    @Autowired
    TestData data;
    @Autowired
    CashService cash;
    @Autowired
    TripService trips;
    @Autowired
    DashboardService dashboard;
    @Autowired
    CashReport report;
    @Autowired
    TransactionTemplate tx;
    @Autowired
    JdbcTemplate jdbc;

    World w;
    Trip trip;

    /** Рейс: заказ 10 шт по 1 000, магазин взял 8 и заплатил 8 000 наличными, ещё 2 000 Kaspi за старый долг, вернул 1 шт негодного. */
    @BeforeEach
    void setUp() {
        w = data.world("Касса");
        data.stockIn(w, 100);
        Order o = data.order(w, data.today(), PaymentMethod.CASH, 10, 1_000);
        trip = data.trip(w, TripStatus.ON_ROAD, o);
        LocalDateTime at = data.today().atTime(11, 0);
        data.delivered(w, o, trip, 8, at);
        data.deliveredFromCar(w, trip, 8);
        data.payment(w, o, trip, PaymentMethod.CASH, 8_000, at);
        data.payment(w, null, trip, PaymentMethod.KASPI, 2_000, at);
        data.returnToCar(w, trip, data.productReturn(w, trip, 1, 1_000, data.today()));
        data.setTripStatus(trip, TripStatus.RETURNED);
    }

    private <T> T as(Supplier<T> action) {
        return TenantContext.call(w.id(), () -> tx.execute(s -> action.get()));
    }

    private Actor operator() {
        return new Actor(w.operator(), w.operator().getName() + " (оператор)");
    }

    @Test
    void недостачаБольшеДопуска_ждётДиректора_наЭкспедитора() {
        as(() -> cash.accept(trip.getId(), 7_500, true, true, null, null, operator(), Role.OPERATOR));
        as(() -> {
            Trip t = trips.get(trip.getId());
            assertThat(t.getStatus()).isEqualTo(TripStatus.RETURNED); // оператор не закрывает — ждёт директора
            assertThat(t.isShortageWaiting()).isTrue();
            assertThat(t.getCashDiff()).isEqualTo(-500);
            assertThat(dashboard.snapshot().alerts(null)).anySatisfy(a -> {
                assertThat(a.text()).startsWith("Недостача 500").endsWith(" — " + w.expeditor().getName());
                assertThat(a.tone()).isEqualTo("bad");
            });
            return null;
        });
        Actor director = new Actor(null, "Директор");
        assertThatThrownBy(() -> as(() -> cash.accept(trip.getId(), 7_500, true, true, null, null, director, Role.DIRECTOR)))
                .isInstanceOf(FormException.class).hasMessageStartingWith("Недостача больше допуска");
        assertThatThrownBy(() -> as(() -> cash.accept(trip.getId(), 7_500, true, true, "WRITE_OFF", " ", director, Role.DIRECTOR)))
                .isInstanceOf(FormException.class).hasMessage("Укажите причину списания недостачи");
        as(() -> cash.accept(trip.getId(), 7_500, true, true, "EXPEDITOR", null, director, Role.DIRECTOR));

        as(() -> {
            Trip t = trips.get(trip.getId());
            assertThat(t.getStatus()).isEqualTo(TripStatus.CLOSED);
            CashHandover h = t.getHandover();
            assertThat(h.getExpectedCash()).isEqualTo(8_000);
            assertThat(h.getKaspiExpected()).isEqualTo(2_000);
            assertThat(h.getCountedCash()).isEqualTo(7_500);
            assertThat(h.getCashDiff()).isEqualTo(-500);
            assertThat(h.getShortageDecision()).isEqualTo(ShortageDecision.EXPEDITOR);
            assertThat(h.getDecidedBy()).isEqualTo("Директор");
            assertThat(h.getExpeditor()).isEqualTo(w.expeditor());
            assertThat(dashboard.snapshot().alerts(null)).noneMatch(a -> a.text().startsWith("Недостача"));
            return null;
        });
        assertThat(as(() -> report.expeditorDebts(w.id())).get(w.expeditor().getId())).isEqualTo(500);
    }

    @Test
    void недостачаВПределахДопуска_закрываетОператор_списаниеСПричиной() {
        if (jdbc.update("update company_settings set cash_tolerance = 500 where company_id = ?", w.id()) == 0)
            jdbc.update("insert into company_settings (company_id, cash_tolerance) values (?, 500)", w.id());
        as(() -> cash.accept(trip.getId(), 7_600, true, true, null, null, operator(), Role.OPERATOR));
        as(() -> {
            CashHandover h = trips.get(trip.getId()).getHandover();
            assertThat(trips.get(trip.getId()).getStatus()).isEqualTo(TripStatus.CLOSED);
            assertThat(h.getShortageDecision()).isEqualTo(ShortageDecision.TOLERANCE);
            assertThat(h.getAcceptedBy()).isEqualTo(w.operator());
            return null;
        });
        assertThat(as(() -> report.expeditorDebts(w.id()))).doesNotContainKey(w.expeditor().getId());
    }

    @Test
    void товарВозвращаетсяНаСклады() {
        as(() -> cash.accept(trip.getId(), 8_000, true, true, null, null, operator(), Role.OPERATOR));
        // загружено 10, выдано 8: 2 — на основной (100 − 10 + 2), 1 негодная — на склад негодного, машина пуста
        assertThat(data.balance(w.main(), w.product())).isEqualTo(92);
        assertThat(data.balance(w.defect(), w.product())).isEqualTo(1);
        assertThat(data.balance(w.car(), w.product())).isZero();
        as(() -> {
            assertThat(trips.get(trip.getId()).getCashDiff()).isZero();
            assertThat(dashboard.snapshot().alerts(null)).noneMatch(a -> a.text().startsWith("Недостача"));
            return null;
        });
    }

    @Test
    void безСверкиKaspiРейсНеЗакрывается() {
        as(() -> cash.accept(trip.getId(), 8_000, false, true, null, null, operator(), Role.OPERATOR));
        as(() -> {
            Trip t = trips.get(trip.getId());
            assertThat(t.getStatus()).isEqualTo(TripStatus.RETURNED);
            assertThat(t.getCashCounted()).isEqualTo(8_000);
            assertThat(t.isGoodsChecked()).isTrue();
            assertThat(t.getHandover().getCashDiff()).isNull();
            return null;
        });
        // повторный приём не возвращает товар второй раз
        as(() -> cash.accept(trip.getId(), 8_000, true, true, null, null, operator(), Role.OPERATOR));
        assertThat(data.balance(w.main(), w.product())).isEqualTo(92);
        as(() -> {
            assertThat(trips.get(trip.getId()).getStatus()).isEqualTo(TripStatus.CLOSED);
            return null;
        });
    }

    @Test
    void рейсВПутиПринимаетсяБезВернулся() {
        data.setTripStatus(trip, TripStatus.ON_ROAD);
        as(() -> {
            Trip t = trips.get(trip.getId());
            assertThat(t.isWaitingCash()).isTrue(); // единственная точка пройдена
            return null;
        });
        as(() -> cash.accept(trip.getId(), 8_000, true, true, null, null, operator(), Role.OPERATOR));
        as(() -> {
            Trip t = trips.get(trip.getId());
            assertThat(t.getStatus()).isEqualTo(TripStatus.CLOSED);
            assertThat(t.isOpen()).isFalse();
            assertThat(t.isWaitingCash()).isFalse();
            return null;
        });
    }

    @Test
    void невыданныйЗаказВозвращаетсяВПринятИОтгружаетсяСнова() {
        Order missed = data.order(w, data.today(), PaymentMethod.CASH, 3, 1_000);
        Trip t2 = data.trip(w, TripStatus.ON_ROAD, missed);
        assertThat(data.balance(w.main(), w.product())).isEqualTo(87);

        as(() -> cash.accept(t2.getId(), 0, true, true, null, null, operator(), Role.OPERATOR));

        assertThat(data.balance(w.main(), w.product())).isEqualTo(90);
        assertThat(jdbc.queryForObject("select status from orders where id = ?", String.class, missed.getId())).isEqualTo("ACCEPTED");
        assertThat(jdbc.queryForObject("select count(*) from trip_orders where order_id = ?", Integer.class, missed.getId())).isZero();
        assertThat(jdbc.queryForObject("select count(*) from order_events where order_id = ? and message like ?", Integer.class,
                missed.getId(), "Не выдан в рейсе " + t2.getNumber() + "%")).isEqualTo(1);
        as(() -> {
            assertThat(trips.get(t2.getId()).getStatus()).isEqualTo(TripStatus.CLOSED);
            return null;
        });

        TripService.Shipment again = as(() -> trips.ship(java.util.List.of(missed.getId()), w.expeditor().getId(), data.today(), operator()));
        assertThat(again.shipped()).isEqualTo(1);
        assertThat(jdbc.queryForObject("select status from orders where id = ?", String.class, missed.getId())).isEqualTo("IN_TRIP");
        // выданный в первом рейсе заказ из рейса не уходит
        assertThat(jdbc.queryForObject("select count(*) from trip_orders where trip_id = ?", Integer.class, trip.getId())).isEqualTo(1);
    }

    @Test
    void закрытыйРейсНеМеняется() {
        as(() -> cash.accept(trip.getId(), 8_000, true, true, null, null, operator(), Role.OPERATOR));
        as(() -> cash.accept(trip.getId(), 1, true, true, null, null, operator(), Role.OPERATOR));
        as(() -> {
            assertThat(trips.get(trip.getId()).getCashCounted()).isEqualTo(8_000);
            return null;
        });
    }
}
