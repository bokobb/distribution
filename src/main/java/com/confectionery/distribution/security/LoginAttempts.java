package com.confectionery.distribution.security;

import com.confectionery.distribution.service.Phones;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Защита входа от подбора пароля — и в приложение (MobileAuthController), и в веб-админку (SecurityConfig), счёт
 * общий на телефон/логин. После пяти неверных паролей подряд — пауза: минута, потом 2, 4, 8 … до часа (с 03.11.2026;
 * раньше пауза всегда была минута — это до 7 000 попыток в сутки, аудит). Сутки без ошибок — паузы снова с минуты.
 * Счётчики в памяти: после перезапуска обнуляются.
 */
@Component
public class LoginAttempts {

    static final int MAX_FAILURES = 5;
    static final Duration PAUSE = Duration.ofMinutes(1);
    static final Duration MAX_PAUSE = Duration.ofMinutes(60);
    static final Duration FORGET_AFTER = Duration.ofHours(24);
    private static final int MAX_TRACKED = 10_000;

    /** failures — ошибок в текущей серии; locks — сколько пауз уже было; lockedUntil — конец текущей паузы. */
    private record State(int failures, int locks, Instant lockedUntil, Instant lastFailure) {
    }

    private final Map<String, State> states = new ConcurrentHashMap<>();
    private final Clock clock;

    public LoginAttempts(Clock clock) {
        this.clock = clock;
    }

    /** Ключ счётчика: телефон в одном виде (+7 701… = 8701…) или логин без регистра. */
    public static String key(String login) {
        if (login == null) return "";
        String phone = Phones.normalize(login);
        return phone != null ? phone : login.strip().toLowerCase(Locale.ROOT);
    }

    /** Сколько секунд ещё ждать; 0 — можно пробовать. */
    public long secondsLeft(String key) {
        State s = states.get(key);
        if (s == null || s.lockedUntil() == null) return 0;
        long left = Duration.between(clock.instant(), s.lockedUntil()).getSeconds();
        return left < 0 ? 0 : left + 1;
    }

    public void failed(String key) {
        Instant now = clock.instant();
        if (states.size() > MAX_TRACKED) {
            states.values().removeIf(s -> s.lastFailure().isBefore(now.minus(FORGET_AFTER))
                    && (s.lockedUntil() == null || s.lockedUntil().isBefore(now)));
        }
        states.compute(key, (k, s) -> {
            if (s == null || s.lastFailure().isBefore(now.minus(FORGET_AFTER))) s = new State(0, 0, null, now);
            boolean pauseOver = s.lockedUntil() != null && !now.isBefore(s.lockedUntil());
            int failures = (pauseOver ? 0 : s.failures()) + 1;
            if (failures < MAX_FAILURES) return new State(failures, s.locks(), pauseOver ? null : s.lockedUntil(), now);
            Duration pause = PAUSE.multipliedBy(1L << Math.min(s.locks(), 6));
            if (pause.compareTo(MAX_PAUSE) > 0) pause = MAX_PAUSE;
            return new State(0, s.locks() + 1, now.plus(pause), now);
        });
    }

    public void succeeded(String key) {
        states.remove(key);
    }

    /** «через 5 мин» / «через 40 сек» — для текста ошибки. */
    public static String waitText(long seconds) {
        return seconds >= 90 ? "через " + ((seconds + 59) / 60) + " мин" : "через " + seconds + " сек";
    }
}
