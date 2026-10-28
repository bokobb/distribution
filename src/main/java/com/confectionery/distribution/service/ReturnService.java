package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.repository.ProductRepository;
import com.confectionery.distribution.repository.ProductReturnRepository;
import com.confectionery.distribution.repository.TripRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.*;

/**
 * Возврат негодного товара экспедитором с телефона: магазин из его незакрытого рейса отдаёт просрочку, брак или
 * товар с плохой упаковкой. Товар — в машину (при приёме рейса уходит на склад негодного), долг магазина
 * уменьшается по цене продажи магазину в день возврата — по прайсу его типа цен. uuid создаёт телефон, поэтому
 * повтор возвращает уже записанный.
 */
@Service
@RequiredArgsConstructor
public class ReturnService {

    /** Время на телефоне может спешить — дальше этого запаса в будущее возврат не принимается. */
    private static final int CLOCK_SKEW_MIN = 10;

    /** Больше стольких штук одного товара за раз — скорее опечатка. */
    private static final int MAX_QTY = 10_000;

    private final ProductReturnRepository returns;
    private final TripRepository trips;
    private final ProductRepository products;
    private final EmployeeRepository employees;
    private final CatalogService catalog;
    private final StockService stock;
    private final DebtService debts;
    private final Clock clock;

    /** reason — EXPIRED, DEFECT или PACKAGING. */
    public record LineIn(Long productId, Integer qty, String reason) {
    }

    /** tripId — рейс, в котором экспедитор у магазина. */
    public record ReturnIn(UUID uuid, Long outletId, Long tripId, LocalDateTime returnedAt, List<LineIn> lines) {
    }

    /** price — по которой уменьшился долг. */
    public record LineOut(Long productId, String name, int qty, long price, long sum, String reason, String reasonLabel) {
    }

    /** total — на сколько уменьшился долг; debt — долг магазина после возврата (минус — аванс). */
    public record ReturnOut(UUID uuid, Long outletId, long total, long debt, List<LineOut> lines) {
    }

    @Transactional
    public ReturnOut save(Long expeditorId, ReturnIn in) {
        if (in.uuid() == null || in.outletId() == null || in.tripId() == null)
            throw new FormException("Возврат без магазина — обновите приложение");
        if (in.lines() == null || in.lines().isEmpty()) throw new FormException("В возврате нет товаров");
        Employee exp = employees.findById(expeditorId).orElseThrow(NotFoundException::new);
        // рейс блокируется: одновременный повтор ждёт и находит уже записанный возврат
        Trip t = trips.lock(in.tripId()).orElseThrow(() -> new FormException("Рейс не найден — обновите данные"));
        ProductReturn was = returns.findByUuid(in.uuid()).orElse(null);
        if (was != null) {
            if (was.getReceivedBy() == null || !was.getReceivedBy().getId().equals(expeditorId))
                throw new FormException("Этот возврат записан другим сотрудником");
            return out(was);
        }
        if (!t.getExpeditor().getId().equals(expeditorId)) throw new FormException("Это не ваш рейс — обновите данные");
        if (!t.isOpen()) throw new FormException("Рейс " + t.getNumber() + " уже закрыт — касса принята");
        Order order = t.getOrders().stream().filter(o -> o.getOutlet().getId().equals(in.outletId())).findFirst()
                .orElseThrow(() -> new FormException("Магазина нет в рейсе " + t.getNumber() + " — обновите данные"));
        Outlet outlet = order.getOutlet();

        LocalDateTime now = LocalDateTime.now(clock);
        LocalDateTime at = in.returnedAt() == null ? now : in.returnedAt();
        if (at.isAfter(now.plusMinutes(CLOCK_SKEW_MIN)))
            throw new FormException("Время возврата неверное — проверьте дату и время на телефоне");
        Map<Long, Long> prices = catalog.pricesOn(outlet.getPriceType(), at.toLocalDate());
        ProductReturn r = new ProductReturn().setUuid(in.uuid()).setOutlet(outlet).setTrip(t).setOrder(order)
                .setDate(at.toLocalDate()).setCreatedAt(at).setReceivedBy(exp);
        r.setCompany(t.getCompany());
        for (LineIn l : in.lines()) {
            if (l.productId() == null || l.qty() == null || l.qty() <= 0 || l.qty() > MAX_QTY)
                throw new FormException("Неверное количество — проверьте возврат");
            Product p = products.findById(l.productId())
                    .orElseThrow(() -> new FormException("Товар не найден — обновите данные на телефоне"));
            Long price = prices.get(p.getId());
            if (price == null) throw new FormException("Нет цены на «" + p.getName() + "» — обратитесь к оператору");
            r.addLine(new ReturnLine().setProduct(p).setQty(l.qty()).setPrice(price).setReason(reason(l.reason())));
        }
        returns.save(r);
        t.getReturns().add(r);
        String who = exp.getName() + " (" + exp.getRole().getLabel().toLowerCase() + ")";
        Actor actor = new Actor(exp, who);
        for (ReturnLine l : r.getLines())
            stock.move(l.getProduct(), l.getQty(), null, stock.warehouse(t.getVehicle()), MovementReason.RETURN, actor, at,
                    m -> m.setTrip(t).setProductReturn(r));
        returns.flush();
        return out(r);
    }

    private static ReturnReason reason(String raw) {
        try {
            return ReturnReason.valueOf(raw);
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new FormException("Укажите причину возврата: просрочка, брак или упаковка");
        }
    }

    private ReturnOut out(ProductReturn r) {
        debts.fill(r.getOutlet());
        List<LineOut> lines = r.getLines().stream().map(l -> new LineOut(l.getProduct().getId(), l.getProduct().getName(),
                l.getQty(), l.getPrice(), l.getSum(), l.getReason().name(), l.getReason().getLabel())).toList();
        return new ReturnOut(r.getUuid(), r.getOutlet().getId(), r.getTotal(), r.getOutlet().getDebt(), lines);
    }
}
