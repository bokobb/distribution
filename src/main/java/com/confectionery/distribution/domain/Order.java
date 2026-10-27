package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/** Заказ агента для магазина. */
@Getter
@Setter
@Accessors(chain = true)
public class Order {
    private Long id;
    private String number;
    private Company company;
    private Outlet outlet;
    private Employee agent;
    private LocalDateTime createdAt;
    private LocalDate deliveryDate;
    private OrderStatus status;
    private PaymentMethod payment;
    private Trip trip;
    private String comment;
    private String refuseReason;
    private List<OrderLine> lines = new ArrayList<>();
    private List<OrderEvent> events = new ArrayList<>();

    public long getTotal() {
        return lines.stream().mapToLong(OrderLine::getSum).sum();
    }

    public long getDeliveredTotal() {
        return lines.stream().mapToLong(OrderLine::getDeliveredSum).sum();
    }

    public int getQty() {
        return lines.stream().mapToInt(OrderLine::getQty).sum();
    }

    public void event(LocalDateTime at, String who, String text) {
        events.add(new OrderEvent(at, who, text));
    }
}
