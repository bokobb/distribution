package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/**
 * Сотрудник компании (пользователь системы). У владельца (SUPER_ADMIN) компании нет — поэтому в
 * режиме одной компании его запись не видна, как и сотрудники других компаний.
 */
@Entity
@Table(name = "users")
@Getter
@Setter
@Accessors(chain = true)
public class Employee extends CompanyEntity {
    private String name;
    @Enumerated(EnumType.STRING)
    private Role role;
    /** Телефон для входа: +7 и 10 цифр (см. Phones). */
    private String phone;
    private String login;
    private String passwordHash;
    /** Пароль выдан временный — при входе сначала сменить. */
    private boolean mustChangePassword = true;
    private boolean active = true;
    /** Последняя синхронизация телефона (агент, экспедитор). */
    private LocalDateTime lastSync;
    /** Записей на телефоне ждут отправки (по последнему сеансу связи). */
    private int unsent;
    private LocalDateTime createdAt;

    /** Экспедитор: закреплённая машина (заполняет сервис для списка сотрудников). */
    @Transient
    private Vehicle vehicle;
    /** Агент: сколько магазинов посещено сегодня (заполняет сервис дашборда). */
    @Transient
    private int visitedToday;

    /** Телефон не выходил на связь больше суток. */
    public boolean isStale() {
        return lastSync != null && lastSync.isBefore(LocalDateTime.now().minusHours(24));
    }

    public String getInitial() {
        return name == null || name.isEmpty() ? "?" : name.substring(0, 1);
    }

    /** Две буквы для кружка: «Ержан Т.» → «ЕТ», «Сауле Ким» → «СК». */
    public String getInitials() {
        if (name == null || name.isBlank()) return "?";
        String[] w = name.strip().split("\\s+");
        return (w[0].substring(0, 1) + (w.length > 1 ? w[1].substring(0, 1) : "")).toUpperCase();
    }
}
