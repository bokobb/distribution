package com.confectionery.distribution.security;

import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.userdetails.User;

import java.util.Collection;

/**
 * Кто вошёл в админку: id сотрудника. Роль и компания каждый раз читаются из базы (AdminContext) —
 * отключённого сотрудника или сменённую роль сервер замечает на следующем же запросе.
 */
public class AdminUser extends User {

    private final Long id;

    public AdminUser(Long id, String username, String passwordHash, boolean enabled,
                     Collection<? extends GrantedAuthority> authorities) {
        super(username, passwordHash, enabled, true, true, true, authorities);
        this.id = id;
    }

    public Long getId() {
        return id;
    }

    @Override
    public boolean equals(Object o) {
        return o instanceof AdminUser u && id.equals(u.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }
}
