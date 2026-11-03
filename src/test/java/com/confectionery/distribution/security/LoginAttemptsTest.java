package com.confectionery.distribution.security;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;

/** Пауза после пяти неверных паролей растёт (1, 2, 4 … 60 мин) и общая для разных записей одного номера. */
class LoginAttemptsTest {

    Instant now = Instant.parse("2026-11-03T10:00:00Z");
    final LoginAttempts attempts = new LoginAttempts(new Clock() {
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    });

    @Test
    void pauseGrowsAndPhoneFormsShareOneCounter() {
        String a = LoginAttempts.key("+7 701 000 00 05");
        String b = LoginAttempts.key("8 701 000 00 05");
        assertThat(a).isEqualTo(b);
        assertThat(LoginAttempts.key(" Olimjon ")).isEqualTo(LoginAttempts.key("olimjon"));

        for (int i = 0; i < 5; i++) attempts.failed(a);
        assertThat(attempts.secondsLeft(b)).isBetween(59L, 61L);

        for (long minutes : new long[]{2, 4, 8, 16, 32, 60, 60}) {
            now = now.plus(Duration.ofMinutes(61));
            assertThat(attempts.secondsLeft(a)).isZero();
            for (int i = 0; i < 5; i++) attempts.failed(a);
            assertThat(attempts.secondsLeft(a)).isBetween(minutes * 60 - 1, minutes * 60 + 1);
        }

        attempts.succeeded(a);
        assertThat(attempts.secondsLeft(a)).isZero();
    }

    @Test
    void waitText() {
        assertThat(LoginAttempts.waitText(40)).isEqualTo("через 40 сек");
        assertThat(LoginAttempts.waitText(3600)).isEqualTo("через 60 мин");
    }
}
