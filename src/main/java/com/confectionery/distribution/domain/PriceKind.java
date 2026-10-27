package com.confectionery.distribution.domain;

/** Тип цен компании: у каждой компании свой прайс опт и розница. */
public enum PriceKind {
    WHOLESALE("Опт"),
    RETAIL("Розница");

    private final String label;

    PriceKind(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
