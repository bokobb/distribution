package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/** Оплата магазина экспедитору (за заказ или в счёт старого долга). */
@Getter
@Setter
@Accessors(chain = true)
public class Payment {
    private Long id;
    private Company company;
    private Outlet outlet;
    /** null — оплата старого долга. */
    private Order order;
    private Trip trip;
    private PaymentMethod method;
    private long amount;
    private LocalDateTime at;
    private String byName;

    public boolean isOldDebt() {
        return order == null;
    }
}
