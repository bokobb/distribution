package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/** Строка истории заказа: когда, кто, что произошло. */
@Entity
@Table(name = "order_events")
@Getter
@Setter
@Accessors(chain = true)
public class OrderEvent extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    @Column(name = "event_at")
    private LocalDateTime at;
    /** Сотрудник; null — «Система» или запись без автора. */
    @ManyToOne(fetch = FetchType.LAZY)
    private Employee user;
    /** Подпись: имя сотрудника, «Система», «Склад». */
    @Column(name = "who_name")
    private String who;
    @Column(name = "message")
    private String text;
}
