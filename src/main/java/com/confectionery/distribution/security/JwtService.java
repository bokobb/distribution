package com.confectionery.distribution.security;

import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.Optional;

/**
 * JWT приложения агента и экспедитора: в нём только id сотрудника, живёт 12 часов. Роль и компанию сервер
 * каждый раз читает из базы (MobileAuthFilter). Подпись — ключом из JWT_SECRET; не задан — случайным при
 * каждом запуске: после перезапуска сервера телефоны сами возьмут новый JWT по ключу устройства.
 */
@Component
public class JwtService {

    private final SecretKey key;
    private final Duration ttl;
    private final Clock clock;

    public JwtService(@Value("${distribution.jwt.secret:}") String secret,
                      @Value("${distribution.jwt.ttl-minutes:720}") long ttlMinutes, Clock clock) {
        byte[] bytes;
        if (secret.isBlank()) {
            bytes = new byte[32];
            new SecureRandom().nextBytes(bytes);
        } else {
            bytes = secret.getBytes(StandardCharsets.UTF_8);
            if (bytes.length < 32) throw new IllegalStateException("JWT_SECRET — не короче 32 знаков");
        }
        this.key = Keys.hmacShaKeyFor(bytes);
        this.ttl = Duration.ofMinutes(ttlMinutes);
        this.clock = clock;
    }

    public String issue(Long userId) {
        Instant now = clock.instant();
        return Jwts.builder()
                .subject(userId.toString())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(ttl)))
                .signWith(key)
                .compact();
    }

    public long ttlSeconds() {
        return ttl.toSeconds();
    }

    /** id сотрудника из действующего JWT; подделан, испорчен или истёк — пусто. */
    public Optional<Long> userId(String token) {
        try {
            String sub = Jwts.parser().verifyWith(key).clock(() -> Date.from(clock.instant())).build()
                    .parseSignedClaims(token).getPayload().getSubject();
            return Optional.of(Long.valueOf(sub));
        } catch (JwtException | IllegalArgumentException e) {
            return Optional.empty();
        }
    }
}
