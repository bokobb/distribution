package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.OrderRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orders;
    private final DebtService debts;
    private final Clock clock;

    /** Заказы по дню доставки: today — развозят сегодня, tomorrow — заказы агентов на завтра и дальше, all — все. */
    public List<Order> byDay(String day) {
        LocalDate today = LocalDate.now(clock);
        return switch (day) {
            case "today" -> orders.findByDeliveryDate(today);
            case "all" -> orders.findAll();
            default -> orders.findByDeliveryDateAfter(today);
        };
    }

    public Order get(Long id) {
        Order o = orders.findById(id).orElseThrow(NotFoundException::new);
        debts.fill(o.getOutlet());
        return o;
    }

    /** Лист сборки: всё принятое на завтра и ещё не загруженное, по маршрутам. */
    public List<Order> toPick() {
        return orders.findByDeliveryDateAfter(LocalDate.now(clock)).stream()
                .filter(o -> o.getStatus() == OrderStatus.ACCEPTED || o.getStatus() == OrderStatus.ASSEMBLED)
                .sorted(Comparator.comparing((Order o) -> o.getOutlet().getRoute() == null ? "" : o.getOutlet().getRoute().getName())
                        .thenComparing(o -> o.getOutlet().getName()))
                .toList();
    }

    /** Лист сборки: товар → штук по всем заказам (рейса или на дату). */
    public record PickRow(Product product, int qty, int boxes, int pieces) {
    }

    public static List<PickRow> pickList(List<Order> list) {
        Map<Product, Integer> m = new LinkedHashMap<>();
        for (Order o : list) for (OrderLine l : o.getLines()) m.merge(l.getProduct(), l.getQty(), Integer::sum);
        return m.entrySet().stream()
                .sorted(Comparator.comparing(e -> e.getKey().getName()))
                .map(e -> {
                    int per = Math.max(1, e.getKey().getPerBox());
                    return new PickRow(e.getKey(), e.getValue(), e.getValue() / per, e.getValue() % per);
                }).toList();
    }

    @Transactional
    public Order approve(Long id, Actor actor) {
        Order o = orders.findById(id).orElseThrow(NotFoundException::new);
        if (o.getStatus() == OrderStatus.NEEDS_APPROVAL) {
            o.setStatus(OrderStatus.ACCEPTED);
            o.event(LocalDateTime.now(clock), actor.entity(), actor.who(), "Разрешил заказ сверх лимита долга");
        }
        return o;
    }

    @Transactional
    public Order cancel(Long id, Actor actor, String reason) {
        Order o = orders.findById(id).orElseThrow(NotFoundException::new);
        if (o.getStatus().cancellable()) {
            o.setStatus(OrderStatus.CANCELLED);
            o.event(LocalDateTime.now(clock), actor.entity(), actor.who(), "Отменил: " + reason);
        }
        return o;
    }
}
