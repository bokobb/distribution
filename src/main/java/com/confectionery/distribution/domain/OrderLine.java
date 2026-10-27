package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Getter
@Setter
@Accessors(chain = true)
public class OrderLine {
    private Product product;
    private int qty;
    private long price;
    /** Выдано экспедитором; null — ещё не выдавали. */
    private Integer delivered;

    public long getSum() {
        return qty * price;
    }

    public long getDeliveredSum() {
        return delivered == null ? 0 : delivered * price;
    }

    public boolean isShortDelivered() {
        return delivered != null && delivered < qty;
    }
}
