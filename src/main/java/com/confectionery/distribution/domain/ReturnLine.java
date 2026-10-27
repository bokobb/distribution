package com.confectionery.distribution.domain;

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

@Entity
@Table(name = "return_items")
@Getter
@Setter
@Accessors(chain = true)
public class ReturnLine extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "return_id")
    private ProductReturn productReturn;
    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;
    private int qty;
    private long price;
    @Enumerated(EnumType.STRING)
    private ReturnReason reason;

    public long getSum() {
        return qty * price;
    }
}
