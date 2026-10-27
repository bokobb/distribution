package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Entity
@Table(name = "price_types")
@Getter
@Setter
@Accessors(chain = true)
public class PriceType extends CompanyEntity {
    @Enumerated(EnumType.STRING)
    private PriceKind code;
    /** «Опт», «Розница». */
    private String name;

    @Override
    public String toString() {
        return name;
    }
}
