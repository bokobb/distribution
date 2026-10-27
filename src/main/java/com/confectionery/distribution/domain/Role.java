package com.confectionery.distribution.domain;

/**
 * Роли. SUPER_ADMIN — владелец производства, видит все компании; остальные привязаны к одной компании.
 * AGENT и EXPEDITOR работают в мобильном приложении, в веб-админку не входят.
 */
public enum Role {
    SUPER_ADMIN("Владелец", "видит все компании"),
    DIRECTOR("Директор", "всё в своей компании"),
    OPERATOR("Оператор", "магазины, долги, касса"),
    STOREKEEPER("Кладовщик", "склад, сборка, рейсы"),
    AGENT("Торговый агент", "приложение"),
    EXPEDITOR("Экспедитор", "приложение");

    private final String label;
    private final String hint;

    Role(String label, String hint) {
        this.label = label;
        this.hint = hint;
    }

    public String getLabel() {
        return label;
    }

    public String getHint() {
        return hint;
    }

    /** Роли, под которыми можно открыть веб-админку. */
    public boolean webAdmin() {
        return this != AGENT && this != EXPEDITOR;
    }
}
