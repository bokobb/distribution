package com.confectionery.distribution.api;

import com.confectionery.distribution.security.MobileAccounts;
import com.confectionery.distribution.security.MobileUser;
import com.confectionery.distribution.service.AgentDataService;
import com.confectionery.distribution.service.AgentDataService.AgentData;
import com.confectionery.distribution.service.AgentDataService.OutletDto;
import com.confectionery.distribution.service.FileStore;
import com.confectionery.distribution.service.MobileOrderService;
import com.confectionery.distribution.service.MobileOrderService.OrderIn;
import com.confectionery.distribution.service.MobileOrderService.OrderOut;
import com.confectionery.distribution.service.OutletCardService;
import com.confectionery.distribution.service.OutletCardService.CardDto;
import com.confectionery.distribution.service.OutletService;
import com.confectionery.distribution.service.OutletService.AgentOutletIn;
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
    private final MobileOrderService orders;
    private final OutletService outlets;
    private final OutletCardService cards;
    private final MobileAccounts accounts;

    /** Данные для работы без сети: настройки, товары и цены, маршруты агента, магазины с долгами, визиты и заказы за сегодня. */
    @GetMapping("/api/mobile/agent/data")
    public AgentData data(@AuthenticationPrincipal MobileUser me) {
        accounts.touch(me.id(), null);
        return data.of(me.id(), me.companyId());
    }

    /** Заказ из магазина; повтор с тем же uuid возвращает уже принятый. */
    @PostMapping("/api/mobile/agent/orders")
    public OrderOut order(@AuthenticationPrincipal MobileUser me, @RequestBody OrderIn in) {
        return orders.save(me.id(), in);
    }

    /** Новый магазин от агента — «на проверке», в конце его маршрута; повтор с тем же uuid возвращает уже добавленный. */
    @PostMapping("/api/mobile/agent/outlets")
    public OutletDto outlet(@AuthenticationPrincipal MobileUser me, @RequestBody AgentOutletIn in) {
        return AgentDataService.outlet(outlets.addByAgent(me.id(), in));
    }

    /** Карточка магазина компании: что он берёт и история визитов с заказами и возвратами (долг — в данных агента). */
    @GetMapping("/api/mobile/agent/outlets/{id}/card")
    public CardDto card(@AuthenticationPrincipal MobileUser me, @PathVariable Long id) {
        return cards.card(me.companyId(), id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Магазин не найден — обновите данные"));
    }

    /** Фото фасада нового магазина — JPEG телом запроса, после самого магазина. */
    @PutMapping("/api/mobile/agent/outlets/{uuid}/photo")
    public ResponseEntity<Void> facade(@AuthenticationPrincipal MobileUser me, @PathVariable UUID uuid,
                                       HttpServletRequest request) throws IOException {
        outlets.facadeByAgent(me.id(), uuid, photo(request));
        return ResponseEntity.noContent().build();
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
        visits.photo(me.id(), uuid, photo(request));
        return ResponseEntity.noContent().build();
    }

    /** Фото телом запроса, не больше FileStore.MAX_PHOTO (и для экспедитора — подтверждение выдачи). */
    static byte[] photo(HttpServletRequest request) throws IOException {
        byte[] jpeg = request.getInputStream().readNBytes(FileStore.MAX_PHOTO + 1);
        if (jpeg.length > FileStore.MAX_PHOTO) throw new ApiException(HttpStatus.CONTENT_TOO_LARGE, "Фото больше 5 МБ");
        return jpeg;
    }
}
