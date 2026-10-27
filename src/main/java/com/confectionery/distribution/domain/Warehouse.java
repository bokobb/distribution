package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Entity
@Table(name = "warehouses")
@Getter
@Setter
@Accessors(chain = true)
public class Warehouse extends CompanyEntity {
    @Enumerated(EnumType.STRING)
    private WarehouseType type;
    private String name;
    /** Только у склада машины. */
    @OneToOne(fetch = FetchType.LAZY)
    private Vehicle vehicle;
}
