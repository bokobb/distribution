package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.service.Actor;

/**
 * Кто смотрит админку и в какой компании. companyId = null — «Все компании» (только у владельца).
 * role — роль, под которой открыта админка (владелец может посмотреть глазами другой роли);
 * owner — вошёл владелец: ему доступны переключатели компании и «Смотреть как».
 */
public record Viewer(Role role, Long companyId, Company company, Employee me, boolean owner) {

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

    /** Подпись в истории: «Сауле Ким (оператор)», у владельца — просто имя. */
    public String who() {
        return me.getName() + (role == Role.SUPER_ADMIN ? "" : " (" + role.getLabel().toLowerCase() + ")");
    }

    public Actor actor() {
        return new Actor(me, who());
    }
}
