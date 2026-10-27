package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/** Возврат негодного товара из магазина (брак и возврат — одно и то же). */
@Getter
@Setter
@Accessors(chain = true)
public class ProductReturn {
    private Long id;
    private Company company;
    private Outlet outlet;
    private Trip trip;
    private LocalDate date;
    private String byName;
    private List<ReturnLine> lines = new ArrayList<>();

    public long getTotal() {
        return lines.stream().mapToLong(ReturnLine::getSum).sum();
    }

    public int getQty() {
        return lines.stream().mapToInt(ReturnLine::getQty).sum();
    }
}
