package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.CashHandoverRepository;
import com.confectionery.distribution.repository.TripOrderRepository;
import com.confectionery.distribution.repository.TripRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Приём рейса вечером: оператор пересчитывает наличные и сверяет Kaspi, кладовщик принимает товар.
 * Рейс закрывается, когда отмечены Kaspi и товар; разница наличных записывается на экспедитора. Принять можно
 * любой незакрытый рейс — экспедитор рейс не закрывает.
 */
@Service
@RequiredArgsConstructor
public class CashService {

    private final TripRepository trips;
    private final TripOrderRepository tripOrders;
    private final CashHandoverRepository handovers;
    private final StockService stock;
    private final Clock clock;

    @Transactional
    public Trip accept(Long tripId, long counted, boolean kaspi, boolean goods, Actor actor) {
        Trip t = trips.findById(tripId).orElseThrow(NotFoundException::new);
        if (!t.isOpen()) return t;
        LocalDateTime now = LocalDateTime.now(clock);
        CashHandover h = t.getHandover();
        if (h == null) {
            h = new CashHandover().setTrip(t).setExpeditor(t.getExpeditor());
            h.setCompany(t.getCompany());
            handovers.save(h);
            t.getHandovers().add(h);
        }
        // ожидаемое — по оплатам рейса на момент приёма
        h.setExpectedCash(t.getCash()).setKaspiExpected(t.getKaspi()).setCountedCash(counted).setKaspiChecked(kaspi);
        if (goods && !h.isGoodsChecked()) {
            unload(t, actor, now);
            h.setGoodsChecked(true);
        }
        if (h.isKaspiChecked() && h.isGoodsChecked()) {
            h.setCashDiff(counted - h.getExpectedCash()).setAcceptedBy(actor.entity()).setAcceptedAt(now);
            t.setStatus(TripStatus.CLOSED).setClosedAt(now);
        }
        return t;
    }

    /**
     * Товар из машины: невыданный — на основной склад, негодный от магазинов — на склад негодного. Заказ, который так
     * и не выдали (не доехал), возвращается в «Принят» и уходит из рейса — его можно отгрузить снова; в истории
     * заказа остаётся, из какого рейса он вернулся.
     */
    private void unload(Trip t, Actor actor, LocalDateTime now) {
        Warehouse car = stock.warehouse(t.getVehicle());
        Warehouse main = stock.warehouse(t.getCompany(), WarehouseType.MAIN);
        Warehouse defect = stock.warehouse(t.getCompany(), WarehouseType.DEFECT);
        Map<Product, Integer> back = new LinkedHashMap<>();
        for (Order o : t.getOrders()) {
            if (o.getStatus() == OrderStatus.CANCELLED) continue;
            for (OrderLine l : o.getLines()) {
                Integer d = l.getDelivered();
                int rest = l.getQty() - (d == null ? 0 : d);
                if (rest > 0) back.merge(l.getProduct(), rest, Integer::sum);
            }
        }
        back.forEach((p, q) -> stock.move(p, q, car, main, MovementReason.UNLOAD, actor, now, m -> m.setTrip(t)));
        Map<Product, Integer> bad = new LinkedHashMap<>();
        for (ProductReturn r : t.getReturns()) for (ReturnLine l : r.getLines()) bad.merge(l.getProduct(), l.getQty(), Integer::sum);
        bad.forEach((p, q) -> stock.move(p, q, car, defect, MovementReason.UNLOAD, actor, now, m -> m.setTrip(t)));
        for (TripOrder to : List.copyOf(t.getTripOrders())) {
            Order o = to.getOrder();
            if (o.getStatus() != OrderStatus.IN_TRIP) continue;
            o.setStatus(OrderStatus.ACCEPTED);
            o.event(now, actor.entity(), actor.who(), "Не выдан в рейсе " + t.getNumber() + " — товар принят на склад, заказ снова «Принят»");
            t.getTripOrders().remove(to);
            tripOrders.delete(to);
        }
    }
}
