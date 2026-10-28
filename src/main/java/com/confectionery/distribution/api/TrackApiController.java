package com.confectionery.distribution.api;

import com.confectionery.distribution.security.MobileAccounts;
import com.confectionery.distribution.security.MobileUser;
import com.confectionery.distribution.service.TrackService;
import com.confectionery.distribution.service.TrackService.Accepted;
import com.confectionery.distribution.service.TrackService.Batch;
import com.confectionery.distribution.service.TrackService.EventIn;
import com.confectionery.distribution.service.TrackService.PointIn;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Журнал приложения и точки GPS с телефона агента и экспедитора — пачкой, когда есть сеть (TrackService:
 * точки только рабочего дня, повтор пачки дублей не создаёт). unsent — сколько записей на телефоне ещё ждут
 * отправки после этой пачки: директор видит его рядом с последней связью телефона.
 */
@RestController
@RequiredArgsConstructor
public class TrackApiController {

    /** Больше за раз телефон не шлёт: остальное — следующей пачкой. */
    static final int MAX_BATCH = 1000;

    private final TrackService track;
    private final MobileAccounts accounts;

    public record TrackRequest(List<EventIn> events, List<PointIn> points, Integer unsent) {
    }

    @PostMapping("/api/mobile/track")
    public Accepted track(@AuthenticationPrincipal MobileUser me, @RequestBody TrackRequest req) {
        int size = (req.events() == null ? 0 : req.events().size()) + (req.points() == null ? 0 : req.points().size());
        if (size > MAX_BATCH) throw new ApiException(HttpStatus.BAD_REQUEST, "Слишком большая пачка — не больше " + MAX_BATCH + " записей");
        Accepted accepted = track.accept(me.id(), new Batch(req.events(), req.points()));
        accounts.touch(me.id(), req.unsent());
        return accepted;
    }
}
