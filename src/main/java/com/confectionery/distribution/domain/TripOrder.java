package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

/** Заказ в рейсе: место в порядке точек. */
@Entity
@Table(name = "trip_orders")
@Getter
@Setter
@Accessors(chain = true)
public class TripOrder extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Trip trip;
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    private int position;
}
