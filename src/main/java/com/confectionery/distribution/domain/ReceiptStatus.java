package com.confectionery.distribution.domain;

public enum ReceiptStatus {
    DRAFT("Ждёт подтверждения", "warn"),
    CONFIRMED("Принят", "done");

    private final String label;
    private final String badge;

    ReceiptStatus(String label, String badge) {
        this.label = label;
        this.badge = badge;
    }

    public String getLabel() {
        return label;
    }

    public String getBadge() {
        return badge;
    }
}
