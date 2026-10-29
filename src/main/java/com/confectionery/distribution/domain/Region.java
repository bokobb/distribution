package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;


@Entity
@Table(name = "regions")
@Getter
@Setter
@Accessors(chain = true)
public class Region extends CompanyEntity {
    private String name;
}
