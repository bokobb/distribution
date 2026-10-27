package com.confectionery.distribution.domain;

public enum ReceiptSource {
    CRM("Из CRM производства"),
    SUPPLIER("От поставщика"),
    MANUAL("Вручную");

    private final String label;

    ReceiptSource(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
