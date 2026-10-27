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
    @Autowired
    com.confectionery.distribution.repository.OrderRepository orderRepo;

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
    void трекGpsСРазрывомИРабочийДень() {
        LocalDateTime day = data.today().atTime(0, 0);
        data.event(w.agent(), day.plusHours(8).plusMinutes(30), AppEventKind.DAY_START);
        data.event(w.agent(), day.plusHours(18), AppEventKind.DAY_END);
        data.point(w.agent(), day.plusHours(9), 42.3000, 69.5800);
        data.point(w.agent(), day.plusHours(9).plusMinutes(5), 42.3090, 69.5800);   // ~1 км к северу
        data.point(w.agent(), day.plusHours(9).plusMinutes(10), 42.3180, 69.5800);  // ещё ~1 км
        data.point(w.agent(), day.plusHours(9).plusMinutes(40), 42.3180, 69.5900);  // после разрыва в 30 минут
        data.point(w.agent(), day.plusHours(9).plusMinutes(45), 42.3180, 69.6000);

        MapService.Person agent = day(List.of(w.agent().getId())).people().get(0);
        assertThat(agent.track()).hasSize(2);
        assertThat(agent.track().get(0)).hasSize(3);
        // путь между кусками неизвестен: 2 км + 0,8 км, а не по прямой через разрыв
        assertThat(agent.km()).isBetween(2.7, 2.9);
        assertThat(agent.summary()).contains("день 08:30–18:00").contains("2,8 км");
        assertThat(day(List.of(w.expeditor().getId())).people().get(0).track()).isEmpty();
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

    @Test
    void заказыНаКартеЦветомТорговогоИЭкспедитора() {
        Order shipped = data.order(w, data.today().plusDays(1), PaymentMethod.CASH, 1, 300);
        data.trip(w, TripStatus.LOADING, shipped);
        Order waiting = data.order(w, second, w.agent(), data.today().plusDays(1), PaymentMethod.KASPI, 2, 100);
        Outlet bare = data.outletInNewRegion(w, w.agent());
        Order noPlace = data.order(w, bare, w.agent(), data.today().plusDays(1), PaymentMethod.CASH, 1, 100);
        MapService.OrdersMap m = TenantContext.call(w.id(), () -> tx.execute(s -> maps.orders(null,
                List.of(orderRepo.findById(shipped.getId()).orElseThrow(), orderRepo.findById(waiting.getId()).orElseThrow(),
                        orderRepo.findById(noPlace.getId()).orElseThrow()), false)));
        assertThat(m.points()).extracting(MapService.OrderPoint::number).containsExactly(shipped.getNumber(), waiting.getNumber());
        assertThat(m.noCoords()).isEqualTo(1);
        MapService.OrderPoint p = m.points().get(0);
        assertThat(p.expeditor()).isEqualTo(w.expeditor().getName());
        assertThat(p.expColor()).isNotEqualTo(MapService.NOT_SHIPPED).isNotEqualTo(p.agentColor());
        assertThat(m.points().get(1).expColor()).isEqualTo(MapService.NOT_SHIPPED);
        assertThat(m.agents()).singleElement().satisfies(l -> {
            assertThat(l.count()).isEqualTo(2);
            assertThat(l.sum()).isEqualTo(500);
        });
        assertThat(m.expeditors()).extracting(MapService.Legend::name).containsExactlyInAnyOrder(w.expeditor().getName(), "Не отгружены");
    }
}
