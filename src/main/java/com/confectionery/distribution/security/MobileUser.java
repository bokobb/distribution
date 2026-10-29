package com.confectionery.distribution.security;

import com.confectionery.distribution.domain.Role;

/**
 * Кто работает в приложении (торговый агент или экспедитор) — читается из базы на каждом запросе.
 * company — название компании; phone — телефон для входа (+77010000104), у входа по логину может не быть;
 * mustChangePassword — пароль временный, сначала сменить.
 */
public record MobileUser(Long id, Long companyId, Role role, String name, String company, String phone,
                         boolean mustChangePassword) {

    public static boolean fieldRole(Role role) {
        return role == Role.AGENT || role == Role.EXPEDITOR;
    }
}
