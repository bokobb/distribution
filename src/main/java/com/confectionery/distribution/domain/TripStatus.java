package com.confectionery.distribution.domain;

/**
 * Рейс: одна машина и один экспедитор на день. Отгрузка из «Заказов» сразу ставит «В пути», приём кассы
 * закрывает; «Загружается» и «Ждёт приёма кассы» — у старых рейсов (кнопок «В путь» и «Вернулся» нет).
 */
public enum TripStatus {
    LOADING("Загружается", "new"),
    ON_ROAD("В пути", "work"),
    RETURNED("Ждёт приёма кассы", "warn"),
    CLOSED("Закрыт", "done");

    private final String label;
    private final String badge;

    TripStatus(String label, String badge) {
        this.label = label;
        this.badge = badge;
    }

    public String getLabel() {
        return label;
    }

    public String getBadge() {
        return badge;
    }

    /** Наличные по рейсу ещё «на руках» у экспедитора. */
    public boolean cashOnHands() {
        return this == ON_ROAD || this == RETURNED;
    }
}
