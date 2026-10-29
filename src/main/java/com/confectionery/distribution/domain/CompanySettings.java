package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalTime;

/** Настройки компании (раздел «Настройки»). */
@Entity
@Table(name = "company_settings")
@Getter
@Setter
@Accessors(chain = true)
public class CompanySettings extends CompanyEntity {
    /** Радиус «агент на месте», метров: дальше — визит помечается. */
    @Column(name = "visit_radius_m")
    private int visitRadius = 200;
    private boolean shelfPhotoRequired;
    private boolean refuseReasonRequired = true;
    /** Доставка по умолчанию: через сколько дней после заказа. */
    private int deliveryDays = 1;
    /** Лимит долга нового магазина, ₸. */
    private long defaultCreditLimit = 50_000;
    private boolean allowCredit = true;
    /** Заказ сверх лимита долга — только с разрешения оператора. */
    private boolean approvalOverLimit = true;
    private boolean agentDiscount;
    /** Допустимая разница при приёме кассы, ₸. */
    private long cashTolerance;
    private boolean acceptKaspi = true;
    /** Создавать приход после отгрузки в CRM. */
    private boolean autoReceipt = true;
    /** Телефон торгового и экспедитора снимает точку GPS раз в столько минут — только в рабочий день. */
    @Column(name = "gps_interval_min")
    private int gpsInterval = 5;
    /** Рабочее время: открыл приложение в это время — день начинается сам, в workEnd — заканчивается сам. */
    private LocalTime workStart = LocalTime.of(8, 0);
    private LocalTime workEnd = LocalTime.of(20, 0);
}
