package com.confectionery.distribution.api;

import com.confectionery.distribution.security.MobileAccounts;
import com.confectionery.distribution.security.MobileUser;
import com.confectionery.distribution.service.AgentDataService;
import com.confectionery.distribution.service.AgentDataService.AgentData;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Адреса приложения торгового агента: /api/mobile/agent/** (только роль AGENT — SecurityConfig). */
@RestController
@RequiredArgsConstructor
public class AgentApiController {

    private final AgentDataService data;
    private final MobileAccounts accounts;

    /** Данные для работы без сети: настройки, товары и цены, маршруты агента, магазины с долгами. */
    @GetMapping("/api/mobile/agent/data")
    public AgentData data(@AuthenticationPrincipal MobileUser me) {
        accounts.touch(me.id(), null);
        return data.of(me.id(), me.companyId());
    }
}
