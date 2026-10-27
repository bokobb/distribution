package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Entity
@Table(name = "order_items")
@Getter
@Setter
@Accessors(chain = true)
public class OrderLine extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;
    private int qty;
    /** Цена за штуку по типу цен магазина на день заказа. */
    private long price;
    /** Скидка на строку, ₸ (может ли агент давать скидку — ещё не решено). */
    private Long discount;

    public long getSum() {
        return qty * price - (discount == null ? 0 : discount);
    }

    /** Цена за штуку с учётом скидки строки. */
    public long getNetPrice() {
        return qty == 0 ? price : getSum() / qty;
    }

    /** Выдано экспедитором; null — ещё не выдавали. */
    public Integer getDelivered() {
        return order == null ? null : order.deliveredQty(product);
    }

    public long getDeliveredSum() {
        Integer d = getDelivered();
        return d == null ? 0 : d * getNetPrice();
    }

    public boolean isShortDelivered() {
        Integer d = getDelivered();
        return d != null && d < qty;
    }
}
