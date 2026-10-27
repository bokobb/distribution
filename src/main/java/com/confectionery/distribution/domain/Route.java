package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.util.ArrayList;
import java.util.List;

/** Маршрут агента: регион, дни недели и магазины по порядку обхода. */
@Getter
@Setter
@Accessors(chain = true)
public class Route {
    private Long id;
    private Company company;
    private Region region;
    private String name;
    private Employee agent;
    /** Дни обхода, например «Пн, Чт». */
    private String days;
    private List<Outlet> outlets = new ArrayList<>();
}
