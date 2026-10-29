package com.confectionery.distribution.domain;

/**
 * Причина возврата негодного товара (брак и возврат — одно и то же: товар не годен для продажи). Её больше не
 * спрашивают — у новых возвратов причины нет; старые телефоны ещё присылают, она сохраняется.
 */
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

    /** Для телефона: EXPIRED, DEFECT, PACKAGING или null. */
    public static String code(ReturnReason r) {
        return r == null ? null : r.name();
    }
}
