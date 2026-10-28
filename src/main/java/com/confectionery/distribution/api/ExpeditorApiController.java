package com.confectionery.distribution.api;

import com.confectionery.distribution.security.MobileAccounts;
import com.confectionery.distribution.security.MobileUser;
import com.confectionery.distribution.service.ExpeditorDataService;
import com.confectionery.distribution.service.ExpeditorDataService.ExpeditorData;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Адреса приложения экспедитора: /api/mobile/expeditor/** (только роль EXPEDITOR — SecurityConfig). */
@RestController
@RequiredArgsConstructor
public class ExpeditorApiController {

    private final ExpeditorDataService data;
    private final MobileAccounts accounts;

    /** Данные для работы без сети: незакрытые рейсы по завтра, точки с заказами и долгами, товары с ценами. */
    @GetMapping("/api/mobile/expeditor/data")
    public ExpeditorData data(@AuthenticationPrincipal MobileUser me) {
        accounts.touch(me.id(), null);
        return data.of(me.id(), me.companyId());
    }
}
