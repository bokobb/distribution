package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;
import org.hibernate.annotations.JoinFormula;

import java.time.LocalDate;
import java.util.UUID;

/** Магазин (торговая точка). */
@Entity
@Table(name = "outlets")
@Getter
@Setter
@Accessors(chain = true)
public class Outlet extends CompanyEntity {
    /** id с телефона агента (новый магазин) или выданный сервером. */
    private UUID uuid = UUID.randomUUID();
    private String name;
    /** ИП или ТОО. */
    private String legal;
    private String bin;
    private String owner;
    private String phone;
    private String phone2;
    private String address;
    /** Ориентир — в сёлах адрес = GPS + ориентир + фото фасада. */
    private String landmark;
    private Double lat;
    private Double lng;
    private String facadePhoto;
    @ManyToOne(fetch = FetchType.LAZY)
    private PriceType priceType;
    private long creditLimit;
    /** Отсрочка оплаты, дней. */
    private int paymentDays;
    @Enumerated(EnumType.STRING)
    private OutletStatus status = OutletStatus.ACTIVE;
    @Column(name = "created_on")
    private LocalDate createdAt;
    /** Кто добавил: агент, сотрудник или «импорт Doctor Sales». */
    private String createdBy;

    /** Маршрут магазина (из route_outlets; менять — через RouteOutlet). */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinFormula("(select ro.route_id from route_outlets ro where ro.outlet_id = id)")
    @Setter(lombok.AccessLevel.NONE)
    private Route route;

    /** Долг считается, а не хранится: начальный + доставлено − оплачено − возвращено (DebtService). */
    @Transient
    private long debt;
    @Transient
    private long overdue;
    @Transient
    private LocalDate lastPaymentDate;
    @Transient
    private long lastPaymentSum;

    public Region getRegion() {
        return route == null ? null : route.getRegion();
    }

    public Employee getAgent() {
        return route == null ? null : route.getAgent();
    }

    /** Долг в процентах от лимита (для полоски), не больше 100. */
    public int getDebtPercent() {
        if (creditLimit <= 0) return debt > 0 ? 100 : 0;
        return (int) Math.max(0, Math.min(100, debt * 100 / creditLimit));
    }

    public boolean isOverLimit() {
        return creditLimit > 0 && debt > creditLimit;
    }
}
