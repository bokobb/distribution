package com.confectionery.distribution.domain;

/** Что ждёт разрешения. LIMIT и OVERDUE — заказ «Нужно разрешение», UNDERPAY — выдача, OUTLET — магазин на проверке. */
public enum ApprovalKind {
    LIMIT("Сверх лимита", "warn"),
    OVERDUE("Заказ закрыт: просрочка", "bad"),
    UNDERPAY("Недоплата при выдаче", "warn"),
    OUTLET("Новый магазин", "new");

    private final String label;
    private final String tone;

    ApprovalKind(String label, String tone) {
        this.label = label;
        this.tone = tone;
    }

    public String getLabel() {
        return label;
    }

    /** Цвет плашки: warn, bad, new. */
    public String getTone() {
        return tone;
    }

    /** Заказы и долги — первая вкладка «Разрешений», новые магазины — вторая. */
    public boolean money() {
        return this != OUTLET;
    }
}
