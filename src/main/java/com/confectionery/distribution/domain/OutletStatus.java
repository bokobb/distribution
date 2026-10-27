package com.confectionery.distribution.domain;

public enum OutletStatus {
    ACTIVE("Работает", "done"),
    PENDING("На проверке", "new"),
    CLOSED("Закрыт", "off");

    private final String label;
    private final String badge;

    OutletStatus(String label, String badge) {
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
