package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Getter
@Setter
@Accessors(chain = true)
public class ReturnLine {
    private Product product;
    private int qty;
    private long price;
    private ReturnReason reason;

    public long getSum() {
        return qty * price;
    }
}
