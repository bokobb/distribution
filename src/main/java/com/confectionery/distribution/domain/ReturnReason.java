package com.confectionery.distribution.domain;

/** Причина возврата негодного товара (брак и возврат — одно и то же: товар не годен для продажи). */
public enum ReturnReason {
    EXPIRED("Просрочка"),
    DEFECT("Брак"),
    PACKAGING("Упаковка");

    private final String label;

    ReturnReason(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
