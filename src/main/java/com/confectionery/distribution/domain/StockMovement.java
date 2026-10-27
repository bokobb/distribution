package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
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

import java.time.LocalDateTime;

/** Движение товара: откуда, куда, по какому документу. Пустой склад — товар пришёл извне или ушёл в магазин. */
@Entity
@Table(name = "stock_movements")
@Getter
@Setter
@Accessors(chain = true)
public class StockMovement extends CompanyEntity {
    private LocalDateTime movedAt;
    @ManyToOne(fetch = FetchType.LAZY)
    private Product product;
    private int qty;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "from_warehouse_id")
    private Warehouse from;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "to_warehouse_id")
    private Warehouse to;
    @Enumerated(EnumType.STRING)
    private MovementReason reason;
    @ManyToOne(fetch = FetchType.LAZY)
    private Receipt receipt;
    @ManyToOne(fetch = FetchType.LAZY)
    private Trip trip;
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "return_id")
    private ProductReturn productReturn;
    @ManyToOne(fetch = FetchType.LAZY)
    private Employee user;
    @Column(length = 200)
    private String note;
}
