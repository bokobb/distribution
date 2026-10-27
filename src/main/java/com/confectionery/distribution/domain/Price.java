package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;

/** Цена товара по типу цен; действует с validFrom до следующей записи. */
@Entity
@Table(name = "prices")
@Getter
@Setter
@Accessors(chain = true)
public class Price extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;
    @ManyToOne(fetch = FetchType.LAZY)
    private PriceType priceType;
    private LocalDate validFrom;
    private long price;
}
