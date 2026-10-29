package com.confectionery.distribution.domain;

/** Что решили по недостаче кассы. */
public enum ShortageDecision {
    EXPEDITOR("на экспедитора"),
    WRITE_OFF("списано"),
    TOLERANCE("в пределах допуска");

    private final String label;

    ShortageDecision(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
