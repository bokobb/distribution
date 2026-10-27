package com.confectionery.distribution.domain;

/** Что сделал сотрудник в приложении или что случилось с телефоном. */
public enum AppEventKind {
    LOGIN("Вход"),
    LOGOUT("Выход"),
    APP_OPEN("Открыл приложение"),
    DAY_START("Начал день"),
    DAY_END("Закончил день"),
    SYNC("Синхронизация"),
    GPS_OFF("GPS выключен"),
    GPS_ON("GPS включён");

    private final String label;

    AppEventKind(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }
}
