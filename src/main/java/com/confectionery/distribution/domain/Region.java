package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "regions")
@Getter
@Setter
@Accessors(chain = true)
public class Region extends CompanyEntity {
    private String name;
    @OneToMany(mappedBy = "region")
    @OrderBy("name")
    private List<Route> routes = new ArrayList<>();
}
