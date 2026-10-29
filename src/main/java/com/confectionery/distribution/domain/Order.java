package com.confectionery.distribution.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;
import org.hibernate.annotations.JoinFormula;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/** Заказ агента для магазина. */
@Entity
@Table(name = "orders")
@Getter
@Setter
@Accessors(chain = true)
public class Order extends CompanyEntity {
    /** id с телефона агента: повторная отправка того же заказа не создаёт дубль. */
    private UUID uuid = UUID.randomUUID();
    private String number;
    @ManyToOne(fetch = FetchType.LAZY)
    private Outlet outlet;
    @ManyToOne(fetch = FetchType.LAZY)
    private Employee agent;
    @ManyToOne(fetch = FetchType.LAZY)
    private Visit visit;
    private LocalDateTime createdAt;
    private LocalDate deliveryDate;
    @Enumerated(EnumType.STRING)
    private OrderStatus status;
    @Enumerated(EnumType.STRING)
    @Column(name = "payment_method")
    private PaymentMethod payment;
    private String comment;
    private String refuseReason;
    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("id")
    private List<OrderLine> lines = new ArrayList<>();
    /** Возврат, который заберёт экспедитор при доставке, — записал торговый. */
    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("id")
    private List<OrderReturnLine> returnLines = new ArrayList<>();
    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("at, id")
    private List<OrderEvent> events = new ArrayList<>();
    /** Выдача экспедитором (не больше одной на заказ). */
    @OneToMany(mappedBy = "order")
    private List<Delivery> deliveries = new ArrayList<>();

    /** Рейс заказа (из trip_orders; менять — через TripOrder). */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinFormula("(select t.trip_id from trip_orders t where t.order_id = id)")
    @Setter(lombok.AccessLevel.NONE)
    private Trip trip;

    public Order addLine(OrderLine line) {
        line.setOrder(this);
        line.setCompany(getCompany());
        lines.add(line);
        return this;
    }

    public Order addReturnLine(OrderReturnLine line) {
        line.setOrder(this);
        line.setCompany(getCompany());
        returnLines.add(line);
        return this;
    }

    public void event(LocalDateTime at, Employee user, String who, String text) {
        OrderEvent e = new OrderEvent().setOrder(this).setAt(at).setUser(user).setWho(who).setText(text);
        e.setCompany(getCompany());
        events.add(e);
    }

    public Delivery getDelivery() {
        return deliveries.isEmpty() ? null : deliveries.get(0);
    }

    /** Выдано штук товара; null — ещё не выдавали или магазин отказался. */
    public Integer deliveredQty(Product p) {
        Delivery d = getDelivery();
        if (d == null || d.getStatus() == DeliveryStatus.REFUSED) return null;
        return d.getItems().stream().filter(i -> i.getProduct().equals(p)).mapToInt(DeliveryItem::getQty).sum();
    }

    public long getTotal() {
        return lines.stream().mapToLong(OrderLine::getSum).sum();
    }

    /** Сколько вычтется за возврат, если экспедитор заберёт всё, что записал торговый. */
    public long getReturnTotal() {
        return returnLines.stream().mapToLong(OrderReturnLine::getSum).sum();
    }

    public long getDeliveredTotal() {
        Delivery d = getDelivery();
        return d == null ? 0 : d.getTotal();
    }

    public int getQty() {
        return lines.stream().mapToInt(OrderLine::getQty).sum();
    }
}
