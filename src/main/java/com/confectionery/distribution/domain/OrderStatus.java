package com.confectionery.distribution.domain;

/**
 * Статусы заказа агента на сервере (черновик живёт только на телефоне, до отправки): «Новый» — пришёл с телефона,
 * «Отгружен» — в рейсе экспедитора на выбранную при отгрузке дату (кнопки «Собран» больше нет, статус остался у старых
 * заказов и отгружается как новый), дальше выдачу
 * отмечает экспедитор. badge — класс плашки в админке (st--new, st--warn, ...).
 */
public enum OrderStatus {
    ACCEPTED("Новый", "new"),
    NEEDS_APPROVAL("Нужно разрешение", "warn"),
    ASSEMBLED("Собран", "ready"),
    IN_TRIP("Отгружен", "work"),
    DELIVERED("Доставлен", "done"),
    PARTIAL("Частично", "part"),
    REFUSED("Отказ магазина", "off"),
    CANCELLED("Отменён", "off");

    private final String label;
    private final String badge;

    OrderStatus(String label, String badge) {
        this.label = label;
        this.badge = badge;
    }

    public String getLabel() {
        return label;
    }

    public String getBadge() {
        return badge;
    }

    /** Заказ ещё можно отменить: до загрузки в машину. */
    public boolean cancellable() {
        return this == ACCEPTED || this == NEEDS_APPROVAL || this == ASSEMBLED;
    }

    /** Ещё не отгружен экспедитору: ждёт сборки, отгрузки или разрешения. */
    public boolean waiting() {
        return this == ACCEPTED || this == NEEDS_APPROVAL || this == ASSEMBLED;
    }

    /** Заказ уже у магазина (выдан целиком или частично). */
    public boolean delivered() {
        return this == DELIVERED || this == PARTIAL;
    }
}
