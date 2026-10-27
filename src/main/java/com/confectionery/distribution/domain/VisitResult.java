package com.confectionery.distribution.domain;

public enum VisitResult {
    ORDER("Заказ"),
    NO_ORDER("Без заказа");

    private final String label;

    VisitResult(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
