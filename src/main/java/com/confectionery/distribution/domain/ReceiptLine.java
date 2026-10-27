package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Getter
@Setter
@Accessors(chain = true)
public class ReceiptLine {
    private Product product;
    /** По документу (для прихода из CRM — сколько отгрузило производство). */
    private int expected;
    /** Фактически принято; null — ещё не пересчитали. */
    private Integer actual;

    public boolean isMismatch() {
        return actual != null && actual != expected;
    }
}
