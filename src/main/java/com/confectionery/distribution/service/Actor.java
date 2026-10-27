package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Employee;

/**
 * Кто делает действие: сотрудник (для ссылки «кто») и подпись для истории («Сауле Ким (оператор)»).
 * user = null — система или запись без автора.
 */
public record Actor(Employee user, String who) {

    public static Actor system(String who) {
        return new Actor(null, who);
    }

    /** Сотрудник, если он есть в базе. */
    public Employee entity() {
        return user != null && user.getId() != null ? user : null;
    }
}
