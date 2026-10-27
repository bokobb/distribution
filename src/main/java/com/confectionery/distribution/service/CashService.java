package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.CashHandoverRepository;
import com.confectionery.distribution.repository.TripRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Приём рейса вечером: оператор пересчитывает наличные и сверяет Kaspi, кладовщик принимает товар.
 * Рейс закрывается, когда отмечены Kaspi и товар; разница наличных записывается на экспедитора.
 */
@Service
@RequiredArgsConstructor
public class CashService {

    private final TripRepository trips;
    private final CashHandoverRepository handovers;
    private final StockService stock;
    private final Clock clock;

    @Transactional
    public Trip accept(Long tripId, long counted, boolean kaspi, boolean goods, Actor actor) {
        Trip t = trips.findById(tripId).orElseThrow(NotFoundException::new);
        if (t.getStatus() != TripStatus.RETURNED) return t;
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

    /** Товар из машины: невыданный — на основной склад, негодный от магазинов — на склад негодного. */
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
    }
}
