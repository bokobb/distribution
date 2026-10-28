package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.repository.PaymentRepository;
import com.confectionery.distribution.repository.TripRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Оплата старого долга экспедитором с телефона: магазин из его незакрытого рейса платит наличными или Kaspi
 * не за заказ, а в счёт долга. Деньги — в кассе рейса («Оплата долгов» при приёме). Больше долга — остаток
 * у магазина авансом (долг уходит в минус). uuid создаёт телефон, поэтому повтор возвращает уже записанную.
 */
@Service
@RequiredArgsConstructor
public class DebtPaymentService {

    /** Время на телефоне может спешить — дальше этого запаса в будущее оплата не принимается. */
    private static final int CLOCK_SKEW_MIN = 10;

    private final PaymentRepository payments;
    private final TripRepository trips;
    private final EmployeeRepository employees;
    private final SettingsService settings;
    private final DebtService debts;
    private final Clock clock;

    /** method — CASH или KASPI; tripId — рейс, в котором экспедитор у магазина. */
    public record PaymentIn(UUID uuid, Long outletId, Long tripId, String method, Long amount, LocalDateTime paidAt) {
    }

    /** debt — долг магазина после этой оплаты (минус — аванс). */
    public record PaymentOut(UUID uuid, Long outletId, String method, long amount, long debt) {
    }

    @Transactional
    public PaymentOut save(Long expeditorId, PaymentIn in) {
        if (in.uuid() == null || in.outletId() == null || in.tripId() == null)
            throw new FormException("Оплата без магазина — обновите приложение");
        if (in.amount() == null || in.amount() <= 0) throw new FormException("Сумма оплаты должна быть больше нуля");
        Employee exp = employees.findById(expeditorId).orElseThrow(NotFoundException::new);
        // рейс блокируется: одновременный повтор ждёт и находит уже записанную оплату
        Trip t = trips.lock(in.tripId()).orElseThrow(() -> new FormException("Рейс не найден — обновите данные"));
        Payment was = payments.findByUuid(in.uuid()).orElse(null);
        if (was != null) {
            if (!was.isOldDebt() || was.getReceivedBy() == null || !was.getReceivedBy().getId().equals(expeditorId))
                throw new FormException("Эта оплата записана другим сотрудником");
            return out(was);
        }
        if (!t.getExpeditor().getId().equals(expeditorId)) throw new FormException("Это не ваш рейс — обновите данные");
        if (!t.isOpen()) throw new FormException("Рейс " + t.getNumber() + " уже закрыт — касса принята");
        Outlet outlet = t.getOrders().stream().map(Order::getOutlet).filter(o -> o.getId().equals(in.outletId()))
                .findFirst().orElseThrow(() -> new FormException("Магазина нет в рейсе " + t.getNumber() + " — обновите данные"));

        LocalDateTime now = LocalDateTime.now(clock);
        LocalDateTime at = in.paidAt() == null ? now : in.paidAt();
        if (at.isAfter(now.plusMinutes(CLOCK_SKEW_MIN)))
            throw new FormException("Время оплаты неверное — проверьте дату и время на телефоне");
        Payment p = new Payment().setUuid(in.uuid()).setOutlet(outlet).setTrip(t)
                .setMethod(DeliveryService.method(in.method(), settings.of(t.getCompanyId())))
                .setAmount(in.amount()).setAt(at).setReceivedBy(exp);
        p.setCompany(t.getCompany());
        t.getPayments().add(payments.saveAndFlush(p));
        return out(p);
    }

    private PaymentOut out(Payment p) {
        debts.fill(p.getOutlet());
        return new PaymentOut(p.getUuid(), p.getOutlet().getId(), p.getMethod().name(), p.getAmount(), p.getOutlet().getDebt());
    }
}
