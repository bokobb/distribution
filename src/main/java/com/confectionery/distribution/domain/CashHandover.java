package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/** Приём рейса вечером: пересчёт наличных (разница — на экспедиторе), сверка Kaspi, приём товара. */
@Entity
@Table(name = "cash_handovers")
@Getter
@Setter
@Accessors(chain = true)
public class CashHandover extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    private Trip trip;
    @ManyToOne(fetch = FetchType.LAZY)
    private Employee expeditor;
    /** Сколько наличных ждали по оплатам рейса на момент приёма. */
    private long expectedCash;
    private Long countedCash;
    /** Пересчитано − ожидалось; минус — недостача на экспедиторе. */
    private Long cashDiff;
    private long kaspiExpected;
    private boolean kaspiChecked;
    private boolean goodsChecked;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "accepted_by")
    private Employee acceptedBy;
    private LocalDateTime acceptedAt;
}
