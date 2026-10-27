package com.confectionery.distribution.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDateTime;

/** Каждую ночь удаляет точки GPS старше 6 месяцев и журнал приложения старше года — у всех компаний. */
@Slf4j
@Service
@RequiredArgsConstructor
public class TrackCleanup {

    public static final int KEEP_POINTS_MONTHS = 6;
    public static final int KEEP_EVENTS_MONTHS = 12;

    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** Сколько удалено: [точек, записей журнала]. */
    @Scheduled(cron = "0 0 3 * * *", zone = "Asia/Almaty")
    public int[] run() {
        LocalDateTime now = LocalDateTime.now(clock);
        int points = jdbc.update("delete from gps_points where recorded_at < ?", now.minusMonths(KEEP_POINTS_MONTHS));
        int events = jdbc.update("delete from app_events where event_at < ?", now.minusMonths(KEEP_EVENTS_MONTHS));
        if (points > 0 || events > 0) log.info("Удалены старые точки GPS: {}, записи журнала приложения: {}", points, events);
        return new int[]{points, events};
    }
}
