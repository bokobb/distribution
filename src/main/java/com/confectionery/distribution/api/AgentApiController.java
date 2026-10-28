package com.confectionery.distribution.api;

import com.confectionery.distribution.security.MobileAccounts;
import com.confectionery.distribution.security.MobileUser;
import com.confectionery.distribution.service.AgentDataService;
import com.confectionery.distribution.service.AgentDataService.AgentData;
import com.confectionery.distribution.service.FileStore;
import com.confectionery.distribution.service.VisitService;
import com.confectionery.distribution.service.VisitService.VisitIn;
import com.confectionery.distribution.service.VisitService.VisitOut;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.util.UUID;

/** Адреса приложения торгового агента: /api/mobile/agent/** (только роль AGENT — SecurityConfig). */
@RestController
@RequiredArgsConstructor
public class AgentApiController {

    private final AgentDataService data;
    private final VisitService visits;
    private final MobileAccounts accounts;

    /** Данные для работы без сети: настройки, товары и цены, маршруты агента, магазины с долгами, визиты за сегодня. */
    @GetMapping("/api/mobile/agent/data")
    public AgentData data(@AuthenticationPrincipal MobileUser me) {
        accounts.touch(me.id(), null);
        return data.of(me.id(), me.companyId());
    }

    /** Законченный визит; повтор с тем же uuid возвращает уже записанный. */
    @PostMapping("/api/mobile/agent/visits")
    public VisitOut visit(@AuthenticationPrincipal MobileUser me, @RequestBody VisitIn in) {
        return visits.save(me.id(), in);
    }

    /** Фото полки к визиту — JPEG телом запроса, после самого визита. */
    @PutMapping("/api/mobile/agent/visits/{uuid}/photo")
    public ResponseEntity<Void> photo(@AuthenticationPrincipal MobileUser me, @PathVariable UUID uuid,
                                      HttpServletRequest request) throws IOException {
        byte[] jpeg = request.getInputStream().readNBytes(FileStore.MAX_PHOTO + 1);
        if (jpeg.length > FileStore.MAX_PHOTO) throw new ApiException(HttpStatus.CONTENT_TOO_LARGE, "Фото больше 5 МБ");
        visits.photo(me.id(), uuid, jpeg);
        return ResponseEntity.noContent().build();
    }
}
