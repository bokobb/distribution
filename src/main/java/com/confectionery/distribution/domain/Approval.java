package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/**
 * Решение по разрешению: кто, когда и что решил. Недоплата при выдаче ждёт решения здесь же (decision пусто),
 * остальное ждёт в своих таблицах — заказ «Нужно разрешение», магазин «На проверке».
 */
@Entity
@Table(name = "approvals")
@Getter
@Setter
@Accessors(chain = true)
public class Approval extends CompanyEntity {
    @Enumerated(EnumType.STRING)
    private ApprovalKind kind;
    @ManyToOne(fetch = FetchType.LAZY)
    private Outlet outlet;
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    /** Что решали: «Заказ З-… · 16 300 ₸ · в долг». */
    private String title;
    /** Расчёт на момент выдачи (только недоплата): строки «подпись=значение» через перевод строки. */
    private String terms;
    private String note;
    private LocalDateTime createdAt;
    private String createdBy;
    /** OK, CASH, DENY, TASK, INFO; пусто — ждёт решения. */
    private String decision;
    private String decisionText;
    private LocalDateTime decidedAt;
    private String decidedBy;
    /** Оплата заказа до «Только оплата при доставке» — чтобы «Вернуть». */
    @Enumerated(EnumType.STRING)
    private PaymentMethod prevPayment;
}
