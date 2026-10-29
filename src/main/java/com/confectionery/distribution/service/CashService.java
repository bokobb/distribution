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
 * Рейс закрывается, когда отмечены Kaspi и товар. Недостача в пределах допуска списывается сама; больше допуска —
 * рейс закрывает директор или владелец (по настройке и оператор): записывает её на экспедитора или списывает с
 * причиной. Пока решения нет, рейс открыт и «ждёт решения». Принять можно любой незакрытый рейс — экспедитор рейс
 * не закрывает.
 */
@Service
@RequiredArgsConstructor
public class CashService {

    private final TripRepository trips;
    private final TripOrderRepository tripOrders;
    private final CashHandoverRepository handovers;
    private final StockService stock;
    private final SettingsService settings;
    private final Clock clock;

    /** decision — EXPEDITOR или WRITE_OFF, нужен только при недостаче больше допуска; reason — причина списания. */
    @Transactional
    public Trip accept(Long tripId, long counted, boolean kaspi, boolean goods, String decision, String reason,
                       Actor actor, Role role) {
        Trip t = trips.findById(tripId).orElseThrow(NotFoundException::new);
        if (!t.isOpen()) return t;
        CompanySettings st = settings.of(t.getCompanyId());
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
        if (!h.isKaspiChecked() || !h.isGoodsChecked()) {
            h.setCashDiff(null);
            return t;
        }
        long diff = counted - h.getExpectedCash();
        ShortageDecision d = null;
        if (diff < 0 && -diff <= st.getCashTolerance()) {
            d = ShortageDecision.TOLERANCE;
        } else if (diff < 0) {
            if (!canDecide(st, role)) {
                h.setCashDiff(diff); // рейс открыт — ждёт решения директора
                return t;
            }
            d = decision(decision, st);
            String why = reason == null ? "" : reason.strip();
            if (d == ShortageDecision.WRITE_OFF && why.length() < 3) throw new FormException("Укажите причину списания недостачи");
            h.setShortageReason(d == ShortageDecision.WRITE_OFF ? cut(why, 200) : null);
        }
        h.setShortageDecision(d).setDecidedBy(d == null ? null : actor.who()).setDecidedAt(d == null ? null : now);
        h.setCashDiff(diff).setAcceptedBy(actor.entity()).setAcceptedAt(now);
        t.setStatus(TripStatus.CLOSED).setClosedAt(now);
        return t;
    }

    /** Недостачу больше допуска решает директор или владелец; если так не настроено — и оператор. */
    public static boolean canDecide(CompanySettings st, Role role) {
        return !st.isShortageDirector() || role == Role.DIRECTOR || role == Role.SUPER_ADMIN;
    }

    private static ShortageDecision decision(String raw, CompanySettings st) {
        if ("EXPEDITOR".equals(raw)) {
            if (!st.isShortageToExpeditor()) throw new FormException("Записывать недостачу на экспедитора выключено в настройках");
            return ShortageDecision.EXPEDITOR;
        }
        if ("WRITE_OFF".equals(raw)) return ShortageDecision.WRITE_OFF;
        throw new FormException("Недостача больше допуска — выберите: записать на экспедитора или списать с причиной");
    }

    private static String cut(String s, int max) {
        return s.length() > max ? s.substring(0, max) : s;
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
