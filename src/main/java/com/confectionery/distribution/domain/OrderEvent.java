package com.confectionery.distribution.domain;

import java.time.LocalDateTime;

/** Строка истории заказа: когда, кто, что произошло. */
public record OrderEvent(LocalDateTime at, String who, String text) {
}
