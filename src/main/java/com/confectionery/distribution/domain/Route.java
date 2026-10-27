package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.DayOfWeek;
import java.util.ArrayList;
import java.util.List;
import java.util.StringJoiner;

/** Маршрут агента: регион, дни недели и магазины по порядку обхода. */
@Entity
@Table(name = "routes")
@Getter
@Setter
@Accessors(chain = true)
public class Route extends CompanyEntity {

    private static final String[] DAY = {"Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"};

    @ManyToOne(fetch = FetchType.LAZY)
    private Region region;
    private String name;
    @ManyToOne(fetch = FetchType.LAZY)
    private Employee agent;
    /** Дни обхода битами: пн = 1, вт = 2, … вс = 64. */
    @Column(name = "days")
    private int daysMask;
    private boolean active = true;
    @OneToMany(mappedBy = "route")
    @OrderBy("position")
    private List<RouteOutlet> stops = new ArrayList<>();

    public static int bit(DayOfWeek d) {
        return 1 << (d.getValue() - 1);
    }

    public boolean visitsOn(DayOfWeek d) {
        return (daysMask & bit(d)) != 0;
    }

    /** Дни обхода, например «Пн, Чт». */
    public String getDays() {
        StringJoiner j = new StringJoiner(", ");
        for (DayOfWeek d : DayOfWeek.values()) if (visitsOn(d)) j.add(DAY[d.ordinal()]);
        return j.length() == 0 ? "—" : j.toString();
    }

    /** Магазины по порядку обхода. */
    public List<Outlet> getOutlets() {
        return stops.stream().map(RouteOutlet::getOutlet).toList();
    }
}
