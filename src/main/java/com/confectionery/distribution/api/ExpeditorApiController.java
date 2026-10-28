package com.confectionery.distribution.api;

import com.confectionery.distribution.security.MobileAccounts;
import com.confectionery.distribution.security.MobileUser;
import com.confectionery.distribution.service.DebtPaymentService;
import com.confectionery.distribution.service.DebtPaymentService.PaymentIn;
import com.confectionery.distribution.service.DebtPaymentService.PaymentOut;
import com.confectionery.distribution.service.DeliveryService;
import com.confectionery.distribution.service.DeliveryService.DeliveryIn;
import com.confectionery.distribution.service.DeliveryService.DeliveryOut;
import com.confectionery.distribution.service.ExpeditorDataService;
import com.confectionery.distribution.service.ExpeditorDataService.ExpeditorData;
import com.confectionery.distribution.service.ReturnService;
import com.confectionery.distribution.service.ReturnService.ReturnIn;
import com.confectionery.distribution.service.ReturnService.ReturnOut;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** Адреса приложения экспедитора: /api/mobile/expeditor/** (только роль EXPEDITOR — SecurityConfig). */
@RestController
@RequiredArgsConstructor
public class ExpeditorApiController {

    private final ExpeditorDataService data;
    private final DeliveryService deliveries;
    private final DebtPaymentService debtPayments;
    private final ReturnService returns;
    private final MobileAccounts accounts;

    /** Данные для работы без сети: незакрытые рейсы по завтра, точки с заказами и долгами, товары с ценами. */
    @GetMapping("/api/mobile/expeditor/data")
    public ExpeditorData data(@AuthenticationPrincipal MobileUser me) {
        accounts.touch(me.id(), null);
        return data.of(me.id(), me.companyId());
    }

    /** Выдача заказа (всё, частично, отказ) и деньги за него; повтор с тем же uuid возвращает уже записанную. */
    @PostMapping("/api/mobile/expeditor/deliveries")
    public DeliveryOut delivery(@AuthenticationPrincipal MobileUser me, @RequestBody DeliveryIn in) {
        return deliveries.save(me.id(), in);
    }

    /** Оплата старого долга магазином из рейса; повтор с тем же uuid возвращает уже записанную. */
    @PostMapping("/api/mobile/expeditor/payments")
    public PaymentOut payment(@AuthenticationPrincipal MobileUser me, @RequestBody PaymentIn in) {
        return debtPayments.save(me.id(), in);
    }

    /** Возврат негодного товара магазином из рейса; повтор с тем же uuid возвращает уже записанный. */
    @PostMapping("/api/mobile/expeditor/returns")
    public ReturnOut productReturn(@AuthenticationPrincipal MobileUser me, @RequestBody ReturnIn in) {
        return returns.save(me.id(), in);
    }
}
