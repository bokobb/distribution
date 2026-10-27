package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Entity
@Table(name = "receipt_items")
@Getter
@Setter
@Accessors(chain = true)
public class ReceiptLine extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Receipt receipt;
    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;
    /** По документу (для прихода из CRM — сколько отгрузило производство). */
    private int expected;
    /** Фактически принято; null — ещё не пересчитали. */
    private Integer actual;

    public boolean isMismatch() {
        return actual != null && actual != expected;
    }
}
