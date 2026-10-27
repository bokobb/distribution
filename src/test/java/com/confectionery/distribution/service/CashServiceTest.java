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
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDateTime;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;

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
    TransactionTemplate tx;

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
    void недостачаЗаписываетсяНаЭкспедитора() {
        as(() -> cash.accept(trip.getId(), 7_500, true, true, operator()));

        as(() -> {
            Trip t = trips.get(trip.getId());
            assertThat(t.getStatus()).isEqualTo(TripStatus.CLOSED);
            CashHandover h = t.getHandover();
            assertThat(h.getExpectedCash()).isEqualTo(8_000);
            assertThat(h.getKaspiExpected()).isEqualTo(2_000);
            assertThat(h.getCountedCash()).isEqualTo(7_500);
            assertThat(h.getCashDiff()).isEqualTo(-500);
            assertThat(h.getExpeditor()).isEqualTo(w.expeditor());
            assertThat(h.getAcceptedBy()).isEqualTo(w.operator());
            assertThat(t.getCashDiff()).isEqualTo(-500);
            assertThat(dashboard.snapshot().alerts(null)).anySatisfy(a -> {
                assertThat(a.text()).isEqualTo("Недостача по рейсу: " + w.expeditor().getName());
                assertThat(a.tone()).isEqualTo("bad");
            });
            return null;
        });
    }

    @Test
    void товарВозвращаетсяНаСклады() {
        as(() -> cash.accept(trip.getId(), 8_000, true, true, operator()));
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
        as(() -> cash.accept(trip.getId(), 8_000, false, true, operator()));
        as(() -> {
            Trip t = trips.get(trip.getId());
            assertThat(t.getStatus()).isEqualTo(TripStatus.RETURNED);
            assertThat(t.getCashCounted()).isEqualTo(8_000);
            assertThat(t.isGoodsChecked()).isTrue();
            assertThat(t.getHandover().getCashDiff()).isNull();
            return null;
        });
        // повторный приём не возвращает товар второй раз
        as(() -> cash.accept(trip.getId(), 8_000, true, true, operator()));
        assertThat(data.balance(w.main(), w.product())).isEqualTo(92);
        as(() -> {
            assertThat(trips.get(trip.getId()).getStatus()).isEqualTo(TripStatus.CLOSED);
            return null;
        });
    }

    @Test
    void закрытыйРейсНеМеняется() {
        as(() -> cash.accept(trip.getId(), 8_000, true, true, operator()));
        as(() -> cash.accept(trip.getId(), 1, true, true, operator()));
        as(() -> {
            assertThat(trips.get(trip.getId()).getCashCounted()).isEqualTo(8_000);
            return null;
        });
    }
}
