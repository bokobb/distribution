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
    /** Магазин на проверке — только оплата при доставке; выключено — в долг до лимита сразу. */
    private boolean firstOrderCash = true;
    /** Заказ закрывается сам при просрочке больше overdueDays дней или больше overdueAmount ₸. */
    private boolean overdueBlock = true;
    private int overdueDays = 14;
    private long overdueAmount = 30_000;
    /** Кто открывает один заказ при просрочке (владелец — всегда). */
    private boolean unblockDirector = true;
    private boolean unblockOperator;
    /** Недоплата при выдаче сверх лимита (или без продажи в долг) — на разрешение. */
    private boolean underpayApproval = true;
    private boolean agentDiscount;
    /** Допустимая разница при приёме кассы, ₸. */
    private long cashTolerance;
    /** Недостача больше допуска — рейс закрывает директор или владелец; выключено — и оператор. */
    private boolean shortageDirector = true;
    /** Недостачу можно записать в долг экспедитора. */
    private boolean shortageToExpeditor = true;
    private boolean acceptKaspi = true;
    /** Создавать приход после отгрузки в CRM. */
    private boolean autoReceipt = true;
    /** Телефон торгового и экспедитора снимает точку GPS раз в столько минут — только в рабочий день. */
    @Column(name = "gps_interval_min")
    private int gpsInterval = 5;
    /** Рабочее время: открыл приложение в это время — день начинается сам, в workEnd — заканчивается сам. */
    private LocalTime workStart = LocalTime.of(8, 0);
    private LocalTime workEnd = LocalTime.of(20, 0);

    /** Магазин закрыт по просрочке — заказ ждёт разрешения. Долг магазина уже посчитан (DebtService.fill). */
    public boolean blocks(Outlet o) {
        return overdueBlock && o.getOverdue() > 0 && (o.getOverdueDays() > overdueDays || o.getOverdue() > overdueAmount);
    }

    /** Кто может открыть один заказ при просрочке: владелец всегда, директор и оператор — по настройке. */
    public boolean unblocks(Role role) {
        return role == Role.SUPER_ADMIN || role == Role.DIRECTOR && unblockDirector || role == Role.OPERATOR && unblockOperator;
    }

    /** «директор и владелец» — для подсказки, кто открывает заказ при просрочке. */
    public String unblockersText() {
        java.util.List<String> who = new java.util.ArrayList<>();
        if (unblockDirector) who.add("директор");
        if (unblockOperator) who.add("оператор");
        who.add("владелец");
        return who.size() == 1 ? who.get(0) : String.join(", ", who.subList(0, who.size() - 1)) + " и " + who.get(who.size() - 1);
    }
}
