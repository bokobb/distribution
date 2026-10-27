package com.confectionery.distribution.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/** Возврат негодного товара из магазина (брак и возврат — одно и то же). */
@Entity
@Table(name = "returns")
@Getter
@Setter
@Accessors(chain = true)
public class ProductReturn extends CompanyEntity {
    private UUID uuid = UUID.randomUUID();
    @ManyToOne(fetch = FetchType.LAZY)
    private Outlet outlet;
    @ManyToOne(fetch = FetchType.LAZY)
    private Trip trip;
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    @Column(name = "return_date")
    private LocalDate date;
    private LocalDateTime createdAt;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "received_by")
    private Employee receivedBy;
    @OneToMany(mappedBy = "productReturn", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("id")
    private List<ReturnLine> lines = new ArrayList<>();

    public ProductReturn addLine(ReturnLine line) {
        line.setProductReturn(this);
        line.setCompany(getCompany());
        lines.add(line);
        return this;
    }

    public long getTotal() {
        return lines.stream().mapToLong(ReturnLine::getSum).sum();
    }

    public int getQty() {
        return lines.stream().mapToInt(ReturnLine::getQty).sum();
    }
}
