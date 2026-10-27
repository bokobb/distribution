package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
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

/** Оплата магазина (за заказ или в счёт старого долга). Наличные или Kaspi; «в долг» — не оплата. */
@Entity
@Table(name = "payments")
@Getter
@Setter
@Accessors(chain = true)
public class Payment extends CompanyEntity {
    private UUID uuid = UUID.randomUUID();
    @ManyToOne(fetch = FetchType.LAZY)
    private Outlet outlet;
    /** null — оплата старого долга. */
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    @ManyToOne(fetch = FetchType.LAZY)
    private Trip trip;
    @Enumerated(EnumType.STRING)
    private PaymentMethod method;
    private long amount;
    @Column(name = "paid_at")
    private LocalDateTime at;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "received_by")
    private Employee receivedBy;

    public boolean isOldDebt() {
        return order == null;
    }
}
