package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

@Entity
@Table(name = "vehicles")
@Getter
@Setter
@Accessors(chain = true)
public class Vehicle extends CompanyEntity {
    private String plate;
    private String model;
    /** Закреплённый экспедитор. */
    @OneToOne(fetch = FetchType.LAZY)
    private Employee expeditor;
    private boolean active = true;
}
