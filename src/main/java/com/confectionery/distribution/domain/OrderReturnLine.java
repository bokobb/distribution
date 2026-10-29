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

/** Что магазин отдаёт назад — торговый записал вместе с заказом, экспедитор заберёт при доставке. Долг не меняет. */
@Entity
@Table(name = "order_return_items")
@Getter
@Setter
@Accessors(chain = true)
public class OrderReturnLine extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;
    private int qty;
    /** Цена за штуку по типу цен магазина на день заказа. */
    private long price;
    @Enumerated(EnumType.STRING)
    private ReturnReason reason;

    public long getSum() {
        return qty * price;
    }
}
