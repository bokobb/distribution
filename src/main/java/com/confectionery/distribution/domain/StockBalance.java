package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

/** Остаток товара на складе. Меняется только вместе с движением (StockService.move). */
@Entity
@Table(name = "stock_balances")
@Getter
@Setter
@Accessors(chain = true)
public class StockBalance extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Warehouse warehouse;
    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;
    private int qty;
}
