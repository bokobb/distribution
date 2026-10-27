package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;

/**
 * Кто смотрит админку и в какой компании. companyId = null — «Все компании» (только у владельца).
 * ЗАГЛУШКА входа: роль выбирается переключателем «Смотреть как» и хранится в сессии; на этапе 1
 * её заменит настоящий вход (Spring Security), а компания у не-владельцев будет из профиля.
 */
public record Viewer(Role role, Long companyId, Company company, Employee me) {

    public boolean isSuper() {
        return role == Role.SUPER_ADMIN;
    }

    public boolean isAll() {
        return companyId == null;
    }

    public boolean can(String sectionKey) {
        AdminSections.Section s = AdminSections.byKey(sectionKey);
        return s != null && s.visibleTo(role);
    }

    /** Подпись области: «Все компании» или название компании. */
    public String scopeName() {
        return company == null ? "Все компании" : company.getName();
    }
}
