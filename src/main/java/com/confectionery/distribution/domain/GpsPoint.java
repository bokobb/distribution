package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/** Точка GPS с телефона торгового или экспедитора — снята в рабочий день. Хранится 6 месяцев. */
@Entity
@Table(name = "gps_points")
@Getter
@Setter
@Accessors(chain = true)
public class GpsPoint extends CompanyEntity {
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private Employee user;
    /** Время на телефоне, когда снята точка. */
    private LocalDateTime recordedAt;
    private double lat;
    private double lng;
    /** Точность по телефону, метров. */
    @Column(name = "accuracy_m")
    private Integer accuracy;
    /** Заряд батареи, %. */
    private Integer battery;
    private LocalDateTime receivedAt;
}
