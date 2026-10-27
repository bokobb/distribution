package com.confectionery.distribution.security;

import com.confectionery.distribution.service.Phones;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.LocalDateTime;

/**
 * Первый владелец (SUPER_ADMIN) — из переменных OWNER_PHONE и OWNER_PASSWORD, если владельца в базе ещё
 * нет. При первом входе система попросит сменить пароль, так что пароль из окружения дальше не
 * действует. Запись — прямым запросом: у владельца нет компании, а сущности компании без неё не пишутся.
 */
@Slf4j
@Component
@Order(0)
@RequiredArgsConstructor
public class OwnerBootstrap implements ApplicationRunner {

    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;
    private final Clock clock;

    @Value("${OWNER_PHONE:}")
    private String ownerPhone;
    @Value("${OWNER_PASSWORD:}")
    private String ownerPassword;
    @Value("${OWNER_NAME:Владелец}")
    private String ownerName;

    @Override
    public void run(ApplicationArguments args) {
        Long owners = jdbc.queryForObject("select count(*) from users where role = 'SUPER_ADMIN'", Long.class);
        if (owners != null && owners > 0) return;
        if (ownerPhone.isBlank() || ownerPassword.isBlank()) {
            log.warn("Владельца в базе нет: задайте OWNER_PHONE и OWNER_PASSWORD (.env) — без него в админку не войти");
            return;
        }
        String phone = Phones.normalize(ownerPhone);
        if (phone == null) throw new IllegalStateException("OWNER_PHONE — телефон +7 и 10 цифр");
        if (ownerPassword.length() < 8) throw new IllegalStateException("OWNER_PASSWORD — не короче 8 знаков");
        Long taken = jdbc.queryForObject("select count(*) from users where phone = ?", Long.class, phone);
        if (taken != null && taken > 0) throw new IllegalStateException("OWNER_PHONE уже у сотрудника компании");
        jdbc.update("insert into users (name, role, phone, password_hash, must_change_password, active, unsent, created_at) "
                        + "values (?, 'SUPER_ADMIN', ?, ?, true, true, 0, ?)",
                ownerName.strip(), phone, encoder.encode(ownerPassword), LocalDateTime.now(clock));
        log.info("Создан владелец {} — при первом входе система попросит сменить пароль", Phones.format(phone));
    }
}
