package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Entity
@Table(name = "delivery_items")
@Getter
@Setter
@Accessors(chain = true)
public class DeliveryItem extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Delivery delivery;
    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;
    private int qty;
    /** Цена за штуку с учётом скидки строки заказа — из неё считается долг. */
    private long price;

    public long getSum() {
        return qty * price;
    }
}
