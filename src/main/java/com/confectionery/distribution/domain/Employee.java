package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/** Сотрудник компании (пользователь системы). */
@Getter
@Setter
@Accessors(chain = true)
public class Employee {
    private Long id;
    /** null — владелец (SUPER_ADMIN), он не привязан к компании. */
    private Company company;
    private String name;
    private Role role;
    private String phone;
    private boolean active = true;
    /** Последняя синхронизация телефона (агент, экспедитор). */
    private LocalDateTime lastSync;
    /** Записей на телефоне ждут отправки (по последнему сеансу связи). */
    private int unsent;
    /** Агент: магазинов на маршрутах сегодня и сколько посещено. */
    private int planToday;
    private int visitedToday;
    /** Экспедитор: закреплённая машина. */
    private Vehicle vehicle;

    /** Телефон не выходил на связь больше суток. */
    public boolean isStale() {
        return lastSync != null && lastSync.isBefore(LocalDateTime.now().minusHours(24));
    }

    public String getInitial() {
        return name == null || name.isEmpty() ? "?" : name.substring(0, 1);
    }
}
