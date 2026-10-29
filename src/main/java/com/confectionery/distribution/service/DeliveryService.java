package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.DeliveryRepository;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.repository.OrderRepository;
import com.confectionery.distribution.repository.PaymentRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.file.Path;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.*;

import static com.confectionery.distribution.service.MobileOrderService.money;

/**
 * Выдача заказа экспедитором с телефона: всё, частично или отказ магазина — и деньги, полученные за этот заказ.
 * uuid выдачи создаёт телефон, поэтому повтор возвращает уже записанную. Выданное уходит из машины, невыданное
 * остаётся в ней до приёма рейса. Цены — из заказа (со скидкой строки); недоплата остаётся долгом магазина.
 */
@Service
@RequiredArgsConstructor
public class DeliveryService {

    /** Время на телефоне может спешить — дальше этого запаса в будущее выдача не принимается. */
    private static final int CLOCK_SKEW_MIN = 10;

    private final DeliveryRepository deliveries;
    private final PaymentRepository payments;
    private final OrderRepository orders;
    private final EmployeeRepository employees;
    private final StockService stock;
    private final SettingsService settings;
    private final FileStore files;
    private final DebtService debts;
    private final ApprovalService approvals;
    private final Clock clock;

    /** Сколько штук товара выдано. */
    public record ItemIn(Long productId, Integer qty) {
    }

    /** method — CASH или KASPI; uuid создаёт телефон. */
    public record PaymentIn(UUID uuid, String method, Long amount) {
    }

    /**
     * refused — магазин отказался (нужна причина), иначе items — сколько выдано по товарам; пусто — выдано всё.
     * payments — сколько получено за этот заказ.
     */
    public record DeliveryIn(UUID uuid, Long orderId, LocalDateTime deliveredAt, boolean refused, String refuseReason,
                             Double lat, Double lng, List<ItemIn> items, List<PaymentIn> payments) {
    }

    /** status — DELIVERED, PARTIAL или REFUSED; total — на сколько выдано; paid — сколько получено. */
    public record DeliveryOut(UUID uuid, Long orderId, String status, String statusLabel, long total, long paid) {
    }

    @Transactional
    public DeliveryOut save(Long expeditorId, DeliveryIn in) {
        if (in.uuid() == null || in.orderId() == null) throw new FormException("Выдача без заказа — обновите приложение");
        Employee exp = employees.findById(expeditorId).orElseThrow(NotFoundException::new);
        // заказ блокируется: одновременный повтор ждёт и находит уже записанную выдачу
        Order o = orders.lockAll(List.of(in.orderId())).stream().findFirst()
                .orElseThrow(() -> new FormException("Заказ не найден — обновите данные на телефоне"));
        Delivery was = deliveries.findByUuid(in.uuid()).orElse(null);
        if (was != null) {
            if (was.getExpeditor() == null || !was.getExpeditor().getId().equals(expeditorId))
                throw new FormException("Эта выдача записана другим сотрудником");
            return out(was);
        }
        Trip t = o.getTrip();
        if (t == null || !t.getExpeditor().getId().equals(expeditorId))
            throw new FormException("Заказа " + o.getNumber() + " нет в вашем рейсе — обновите данные");
        if (!t.isOpen()) throw new FormException("Рейс " + t.getNumber() + " уже закрыт — касса принята");
        if (o.getStatus() != OrderStatus.IN_TRIP)
            throw new FormException("Заказ " + o.getNumber() + " уже «" + o.getStatus().getLabel() + "» — обновите данные");

        LocalDateTime now = LocalDateTime.now(clock);
        LocalDateTime at = in.deliveredAt() == null ? now : in.deliveredAt();
        debts.fill(o.getOutlet()); // долг до этой выдачи — для недоплаты сверх лимита
        if (at.isAfter(now.plusMinutes(CLOCK_SKEW_MIN)))
            throw new FormException("Время выдачи неверное — проверьте дату и время на телефоне");
        String who = exp.getName() + " (" + exp.getRole().getLabel().toLowerCase() + ")";
        Actor actor = new Actor(exp, who);
        Delivery d = new Delivery().setUuid(in.uuid()).setOrder(o).setTrip(t).setDeliveredAt(at).setExpeditor(exp)
                .setLat(in.lat()).setLng(in.lng());
        d.setCompany(o.getCompany());

        if (in.refused()) {
            String reason = in.refuseReason() == null ? "" : in.refuseReason().strip();
            if (reason.isEmpty()) throw new FormException("Укажите, почему магазин отказался");
            if (in.payments() != null && !in.payments().isEmpty()) throw new FormException("При отказе оплаты нет");
            d.setStatus(DeliveryStatus.REFUSED).setRefuseReason(cut(reason, 300));
            o.setStatus(OrderStatus.REFUSED).setRefuseReason(cut(reason, 300));
            o.event(at, exp, who, "Отказ магазина: " + reason);
            deliveries.save(d);
            return out(d);
        }

        Map<Long, Integer> given = new HashMap<>();
        if (in.items() != null) for (ItemIn i : in.items()) {
            if (i.productId() == null || i.qty() == null || i.qty() < 0) throw new FormException("Неверное количество — проверьте выдачу");
            given.merge(i.productId(), i.qty(), Integer::sum);
        }
        Set<Long> inOrder = new HashSet<>();
        o.getLines().forEach(l -> inOrder.add(l.getProduct().getId()));
        if (!inOrder.containsAll(given.keySet())) throw new FormException("В выдаче товар не из заказа — обновите данные");
        Warehouse car = stock.warehouse(t.getVehicle());
        boolean full = true;
        for (OrderLine l : o.getLines()) {
            int q = in.items() == null || in.items().isEmpty() ? l.getQty() : given.getOrDefault(l.getProduct().getId(), 0);
            if (q > l.getQty())
                throw new FormException("«" + l.getProduct().getName() + "» выдано больше, чем в заказе (" + l.getQty() + ")");
            if (q < l.getQty()) full = false;
            if (q == 0) continue;
            d.addItem(new DeliveryItem().setProduct(l.getProduct()).setQty(q).setPrice(l.getNetPrice()));
            try {
                stock.move(l.getProduct(), q, car, null, MovementReason.DELIVERY, actor, at, m -> m.setTrip(t).setOrder(o));
            } catch (IllegalStateException e) {
                throw new FormException(e.getMessage());
            }
        }
        if (d.getItems().isEmpty()) throw new FormException("Ничего не выдано — отметьте отказ магазина");
        d.setStatus(full ? DeliveryStatus.DELIVERED : DeliveryStatus.PARTIAL);
        deliveries.save(d);
        o.setStatus(full ? OrderStatus.DELIVERED : OrderStatus.PARTIAL);
        o.event(at, exp, who, full ? "Выдан полностью на " + money(d.getTotal())
                : "Выдан частично на " + money(d.getTotal()) + " из " + money(o.getTotal()));

        CompanySettings st = settings.of(o.getCompanyId());
        List<PaymentIn> got = in.payments() == null ? List.of()
                : in.payments().stream().filter(p -> p.amount() != null && p.amount() > 0).toList();
        long paid = got.stream().mapToLong(PaymentIn::amount).sum();
        if (paid > d.getTotal())
            throw new FormException("Получено " + money(paid) + " — больше выданного (" + money(d.getTotal())
                    + "). Остальное примите как оплату долга");
        for (PaymentIn p : got) {
            Payment pay = new Payment().setUuid(p.uuid() == null ? UUID.randomUUID() : p.uuid()).setOutlet(o.getOutlet())
                    .setOrder(o).setTrip(t).setMethod(method(p.method(), st)).setAmount(p.amount()).setAt(at).setReceivedBy(exp);
            pay.setCompany(o.getCompany());
            t.getPayments().add(payments.save(pay));
        }
        if (paid > 0) o.event(at, exp, who, "Получено " + money(paid));
        if (o.getPayment() != PaymentMethod.CREDIT && paid < d.getTotal()) {
            o.event(at, exp, who, "Недоплата " + money(d.getTotal() - paid) + " — в долг магазина");
            approvals.underpay(o, d.getTotal(), paid, o.getOutlet().getDebt(), st, actor, at);
        }
        return out(d);
    }

    /** Подпись получателя или фото накладной к своей выдаче — после самой выдачи; повтор заменяет файл. */
    @Transactional
    public void proof(Long expeditorId, UUID uuid, byte[] image) {
        Delivery d = deliveries.findByUuid(uuid)
                .filter(x -> x.getExpeditor() != null && x.getExpeditor().getId().equals(expeditorId))
                .orElseThrow(NotFoundException::new);
        if (d.getStatus() == DeliveryStatus.REFUSED) throw new FormException("При отказе подтверждение не нужно");
        d.setProof(files.saveProof(d.getCompanyId(), uuid, image));
    }

    /** Файл подтверждения к выдаче своей компании — для админки. */
    @Transactional(readOnly = true)
    public Optional<Path> proofFile(UUID uuid) {
        return deliveries.findByUuid(uuid).map(Delivery::getProof).flatMap(files::find);
    }

    /** Наличные — всегда; Kaspi — если компания принимает. */
    static PaymentMethod method(String raw, CompanySettings st) {
        PaymentMethod m;
        try {
            m = raw == null ? null : PaymentMethod.valueOf(raw);
        } catch (IllegalArgumentException e) {
            m = null;
        }
        if (m == null || m == PaymentMethod.CREDIT) throw new FormException("Оплата — наличными или Kaspi");
        if (m == PaymentMethod.KASPI && !st.isAcceptKaspi()) throw new FormException("Kaspi компания не принимает");
        return m;
    }

    private static DeliveryOut out(Delivery d) {
        long paid = d.getTrip() == null ? 0 : d.getTrip().getPayments().stream()
                .filter(p -> p.getOrder() != null && p.getOrder().getId().equals(d.getOrder().getId()))
                .mapToLong(Payment::getAmount).sum();
        return new DeliveryOut(d.getUuid(), d.getOrder().getId(), d.getStatus().name(), d.getOrder().getStatus().getLabel(),
                d.getTotal(), paid);
    }

    private static String cut(String s, int max) {
        return s.length() > max ? s.substring(0, max) : s;
    }
}
