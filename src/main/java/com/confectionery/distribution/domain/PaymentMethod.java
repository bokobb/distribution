package com.confectionery.distribution.domain;

public enum PaymentMethod {
    CASH("Наличные"),
    KASPI("Kaspi"),
    CREDIT("В долг");

    private final String label;

    PaymentMethod(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
