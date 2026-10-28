package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.Visit;
import com.confectionery.distribution.domain.VisitResult;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.repository.OutletRepository;
import com.confectionery.distribution.repository.RouteRepository;
import com.confectionery.distribution.repository.VisitRepository;
import com.confectionery.distribution.service.GpsTrack.At;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.file.Path;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Визиты торгового агента с телефона. Телефон записывает визит без сети и шлёт его, когда агент закончил
 * визит; uuid создаёт телефон, поэтому повтор не создаёт второй визит. Расстояние до магазина сервер
 * считает сам по точке отметки и координатам магазина. Фото полки — отдельным запросом после визита.
 */
@Service
@RequiredArgsConstructor
public class VisitService {

    /** Время на телефоне может спешить — дальше этого запаса в будущее визит не принимается. */
    private static final int CLOCK_SKEW_MIN = 10;

    private final VisitRepository visits;
    private final EmployeeRepository employees;
    private final OutletRepository outlets;
    private final RouteRepository routes;
    private final SettingsService settings;
    private final FileStore files;
    private final Clock clock;

    /** result — ORDER или NO_ORDER; lat/lng — где агент отметился в магазине. */
    public record VisitIn(UUID uuid, Long outletId, Long routeId, LocalDateTime startedAt, LocalDateTime finishedAt,
                          Double lat, Double lng, String result, String refuseReason) {
    }

    /** distance — метров до магазина (нет координат — null); photo — фото полки уже на сервере. */
    public record VisitOut(UUID uuid, Long outletId, LocalDateTime startedAt, LocalDateTime finishedAt, String result,
                           String refuseReason, Integer distance, boolean photo) {
    }

    @Transactional
    public VisitOut save(Long agentId, VisitIn in) {
        if (in.uuid() == null || in.outletId() == null || in.startedAt() == null)
            throw new FormException("Визит без магазина или времени — обновите приложение");
        Visit was = visits.findByUuid(in.uuid()).orElse(null);
        if (was != null) {
            if (!was.getAgent().getId().equals(agentId)) throw new FormException("Этот визит записан другим сотрудником");
            return out(was);
        }
        LocalDateTime latest = LocalDateTime.now(clock).plusMinutes(CLOCK_SKEW_MIN);
        if (in.startedAt().isAfter(latest) || in.finishedAt() != null
                && (in.finishedAt().isBefore(in.startedAt()) || in.finishedAt().isAfter(latest)))
            throw new FormException("Время визита неверное — проверьте дату и время на телефоне");
        VisitResult result = result(in.result());
        Employee agent = employees.findById(agentId).orElseThrow(NotFoundException::new);
        Outlet outlet = outlets.findById(in.outletId())
                .orElseThrow(() -> new FormException("Магазин не найден — обновите данные на телефоне"));
        String reason = result == VisitResult.ORDER ? null : cut(in.refuseReason(), 200);
        if (result == VisitResult.NO_ORDER && reason == null && settings.of(agent.getCompanyId()).isRefuseReasonRequired())
            throw new FormException("Укажите, почему без заказа");

        Visit v = new Visit().setUuid(in.uuid()).setAgent(agent).setOutlet(outlet)
                .setRoute(in.routeId() == null ? null : routes.findById(in.routeId()).orElse(null))
                .setStartedAt(in.startedAt()).setFinishedAt(in.finishedAt()).setResult(result).setRefuseReason(reason);
        if (in.lat() != null && in.lng() != null && Math.abs(in.lat()) <= 90 && Math.abs(in.lng()) <= 180
                && !(in.lat() == 0 && in.lng() == 0)) {
            v.setLat(in.lat()).setLng(in.lng());
            if (outlet.getLat() != null && outlet.getLng() != null)
                v.setDistance((int) Math.round(GpsTrack.km(new At(null, in.lat(), in.lng()),
                        new At(null, outlet.getLat(), outlet.getLng())) * 1000));
        }
        return out(visits.save(v));
    }

    /** Фото полки к своему визиту; повтор заменяет файл. */
    @Transactional
    public void photo(Long agentId, UUID uuid, byte[] jpeg) {
        Visit v = visits.findByUuid(uuid).filter(x -> x.getAgent().getId().equals(agentId)).orElseThrow(NotFoundException::new);
        v.setShelfPhoto(files.savePhoto(v.getCompanyId(), "visits", uuid, jpeg));
    }

    /** Файл фото полки к визиту своей компании — для админки. */
    @Transactional(readOnly = true)
    public Optional<Path> photoFile(UUID uuid) {
        return visits.findByUuid(uuid).map(Visit::getShelfPhoto).flatMap(files::find);
    }

    /** Визиты агента за день — телефону: отметки «был в магазине» переживают переустановку приложения. */
    @Transactional(readOnly = true)
    public List<VisitOut> of(Long agentId, LocalDate day) {
        return visits.findByAgentIdAndStartedAtGreaterThanEqualAndStartedAtLessThanOrderByStartedAtAsc(agentId,
                day.atStartOfDay(), day.plusDays(1).atStartOfDay()).stream().map(VisitService::out).toList();
    }

    private static VisitOut out(Visit v) {
        return new VisitOut(v.getUuid(), v.getOutlet().getId(), v.getStartedAt(), v.getFinishedAt(), v.getResult().name(),
                v.getRefuseReason(), v.getDistance(), v.getShelfPhoto() != null);
    }

    private static VisitResult result(String s) {
        try {
            return VisitResult.valueOf(s);
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new FormException("Неверный итог визита — обновите приложение");
        }
    }

    private static String cut(String s, int max) {
        if (s == null || s.isBlank()) return null;
        s = s.strip();
        return s.length() > max ? s.substring(0, max) : s;
    }
}
