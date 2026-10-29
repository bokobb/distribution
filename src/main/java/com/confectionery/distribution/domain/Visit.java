package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;
import java.util.UUID;

/** Визит агента в магазин: с заказом или без (тогда — причина). */
@Entity
@Table(name = "visits")
@Getter
@Setter
@Accessors(chain = true)
public class Visit extends CompanyEntity {
    private UUID uuid = UUID.randomUUID();
    @ManyToOne(fetch = FetchType.LAZY)
    private Employee agent;
    @ManyToOne(fetch = FetchType.LAZY)
    private Outlet outlet;
    private LocalDateTime startedAt;
    private LocalDateTime finishedAt;
    private Double lat;
    private Double lng;
    /** Расстояние до точки магазина, метров. */
    @Column(name = "distance_m")
    private Integer distance;
    @Enumerated(EnumType.STRING)
    private VisitResult result;
    private String refuseReason;
    private String shelfPhoto;
}
