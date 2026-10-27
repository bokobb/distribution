package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;

/** Магазин (торговая точка). */
@Getter
@Setter
@Accessors(chain = true)
public class Outlet {
    private Long id;
    private Company company;
    private Route route;
    private String name;
    /** ИП или ТОО. */
    private String legal;
    private String bin;
    private String owner;
    private String phone;
    private String address;
    private Double lat;
    private Double lng;
    /** Тип цен: «Опт», «Розница». */
    private String priceType;
    private long creditLimit;
    private long debt;
    private long overdue;
    private int paymentDays;
    private OutletStatus status = OutletStatus.ACTIVE;
    private LocalDate lastPaymentDate;
    private long lastPaymentSum;
    private LocalDate createdAt;
    private String createdBy;

    public Region getRegion() {
        return route == null ? null : route.getRegion();
    }

    public Employee getAgent() {
        return route == null ? null : route.getAgent();
    }

    /** Долг в процентах от лимита (для полоски), не больше 100. */
    public int getDebtPercent() {
        if (creditLimit <= 0) return debt > 0 ? 100 : 0;
        return (int) Math.min(100, debt * 100 / creditLimit);
    }

    public boolean isOverLimit() {
        return creditLimit > 0 && debt > creditLimit;
    }
}
