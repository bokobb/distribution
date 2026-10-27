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
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** Карта дня: пути людей по времени, точка без отметки — магазин, цвет магазина — его торговый, только своя компания. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class MapServiceTest {

    @Autowired
    TestData data;
    @Autowired
    MapService maps;
    @Autowired
    TransactionTemplate tx;

    World w, other;
    Outlet second;

    @BeforeEach
    void setUp() {
        w = data.world("Карта");
        other = data.world("Чужая карта");
        second = data.outletInNewRegion(w, w.agent());
        data.place(w.outlet(), 42.30, 69.58);
        data.place(second, 42.31, 69.60);
        data.place(other.outlet(), 42.40, 69.70);
        LocalDateTime day = data.today().atTime(0, 0);
        data.visit(w, second, day.plusHours(11), VisitResult.NO_ORDER, null, null);       // без отметки — точка магазина
        data.visit(w, w.outlet(), day.plusHours(10), VisitResult.ORDER, 42.3001, 69.5801);
        data.visit(other, other.outlet(), day.plusHours(9), VisitResult.ORDER, 42.40, 69.70);
        data.stockIn(w, 10);
        Order o = data.order(w, data.today(), PaymentMethod.CASH, 2, 100);
        Trip t = data.trip(w, TripStatus.ON_ROAD, o);
        data.delivered(w, o, t, 2, day.plusHours(12));
    }

    private MapService.Day day(List<Long> who) {
        return TenantContext.call(w.id(), () -> tx.execute(s -> maps.day(null, data.today(), who)));
    }

    @Test
    void путиПоВремениИМагазины() {
        MapService.Day d = day(List.of());
        assertThat(d.people()).extracting(MapService.Person::name).containsExactly(w.agent().getName(), w.expeditor().getName());
        MapService.Person agent = d.people().get(0);
        assertThat(agent.stops()).extracting(MapService.Stop::time).containsExactly("10:00", "11:00");
        assertThat(agent.stops().get(0).lat()).isEqualTo(42.3001);
        assertThat(agent.stops().get(1).lat()).isEqualTo(42.31);
        assertThat(agent.stops()).extracting(MapService.Stop::kind).containsExactly("ORDER", "NO_ORDER");
        assertThat(agent.summary()).startsWith("визитов 2").contains("с заказом 1").contains("10:00–11:00");
        assertThat(d.people().get(1).stops()).extracting(MapService.Stop::kind).containsExactly("DELIVERED");

        assertThat(d.outlets()).extracting(MapService.Shop::id).containsExactlyInAnyOrder(w.outlet().getId(), second.getId());
        assertThat(d.outlets()).extracting(MapService.Shop::color).containsOnly(agent.color());
        assertThat(d.noCoords()).isZero();
    }

    @Test
    void выбранТолькоЭкспедитор() {
        MapService.Day d = day(List.of(w.expeditor().getId()));
        assertThat(d.people()).extracting(MapService.Person::name).containsExactly(w.expeditor().getName());
        assertThat(d.outlets()).hasSize(2);
    }

    @Test
    void магазиныБезКоординатСчитаются() {
        Outlet bare = data.outletInNewRegion(w, w.agent());
        MapService.Day d = day(List.of());
        assertThat(d.noCoords()).isEqualTo(1);
        assertThat(d.outlets()).extracting(MapService.Shop::id).doesNotContain(bare.getId());
    }
}
