package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;

/** Долг магазина на день импорта (Doctor Sales) или ввода вручную. С asOf считается отсрочка. */
@Entity
@Table(name = "outlet_opening_debts")
@Getter
@Setter
@Accessors(chain = true)
public class OutletOpeningDebt extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Outlet outlet;
    /** Минус — переплата магазина. */
    private long amount;
    private LocalDate asOf;
    private String note;
}
