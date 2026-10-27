package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

/** Магазин на маршруте: место в порядке обхода. Пока у магазина один маршрут. */
@Entity
@Table(name = "route_outlets")
@Getter
@Setter
@Accessors(chain = true)
public class RouteOutlet extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Route route;
    @ManyToOne(fetch = FetchType.LAZY)
    private Outlet outlet;
    private int position;
}
