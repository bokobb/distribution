package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;
import java.util.UUID;

/** Запись журнала приложения: вход, начало и конец дня, синхронизация, GPS. Хранится год. */
@Entity
@Table(name = "app_events")
@Getter
@Setter
@Accessors(chain = true)
public class AppEvent extends CompanyEntity {
    private UUID uuid = UUID.randomUUID();
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private Employee user;
    private LocalDateTime eventAt;
    @Enumerated(EnumType.STRING)
    private AppEventKind kind;
    private String appVersion;
    /** Модель телефона. */
    private String device;
    private String note;
    private LocalDateTime receivedAt;
}
