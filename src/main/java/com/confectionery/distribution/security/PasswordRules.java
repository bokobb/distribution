package com.confectionery.distribution.security;

import org.springframework.security.crypto.password.PasswordEncoder;

import java.nio.charset.StandardCharsets;

/** Правила смены пароля — одни для админки и приложения. */
public final class PasswordRules {

    private PasswordRules() {
    }

    /** Что не так с новым паролем (текст для человека); null — можно сохранять. */
    public static String problem(PasswordEncoder encoder, String current, String password, String confirm, String hash, String phone) {
        if (hash == null || current == null || !encoder.matches(current, hash)) return "Текущий пароль неверный";
        if (password == null || password.length() < 8) return "Новый пароль — не короче 8 знаков";
        if (password.getBytes(StandardCharsets.UTF_8).length > 72) return "Новый пароль слишком длинный";
        if (!password.equals(confirm)) return "Новый пароль и повтор не совпадают";
        if (password.equals(current)) return "Новый пароль совпадает с прежним";
        String digits = password.replaceAll("\\D", "");
        if (!digits.isEmpty() && phone.endsWith(digits) && digits.length() >= 7) return "Пароль не должен быть номером телефона";
        return null;
    }
}
