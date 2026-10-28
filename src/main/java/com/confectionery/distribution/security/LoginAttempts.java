package com.confectionery.distribution.security;

import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Защита входа приложения от подбора, как в CRM: после пяти неверных паролей подряд для одного телефона
 * следующая попытка — через минуту. Счётчики в памяти: после перезапуска обнуляются, против перебора хватает.
 */
@Component
public class LoginAttempts {

    static final int MAX_FAILURES = 5;
    static final Duration PAUSE = Duration.ofMinutes(1);

    private record State(int failures, Instant lockedUntil) {
    }

    private final Map<String, State> states = new ConcurrentHashMap<>();
    private final Clock clock;

    public LoginAttempts(Clock clock) {
        this.clock = clock;
    }

    /** Сколько секунд ещё ждать; 0 — можно пробовать. */
    public long secondsLeft(String key) {
        State s = states.get(key);
        if (s == null || s.lockedUntil() == null) return 0;
        long left = Duration.between(clock.instant(), s.lockedUntil()).getSeconds();
        return Math.max(0, left + 1);
    }

    public void failed(String key) {
        Instant now = clock.instant();
        states.compute(key, (k, s) -> {
            int n = s == null || s.lockedUntil() != null && now.isAfter(s.lockedUntil()) ? 1 : s.failures() + 1;
            return new State(n, n >= MAX_FAILURES ? now.plus(PAUSE) : null);
        });
    }

    public void succeeded(String key) {
        states.remove(key);
    }
}
