package com.confectionery.distribution.domain;

/** Склады компании: основной, негодный товар и склад каждой машины. */
public enum WarehouseType {
    MAIN("Основной"),
    DEFECT("Негодный товар"),
    VEHICLE("Машина");

    private final String label;

    WarehouseType(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
