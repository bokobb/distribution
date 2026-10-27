package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/** Рейс: машина + экспедитор на день, заказы по порядку точек. */
@Getter
@Setter
@Accessors(chain = true)
public class Trip {
    private Long id;
    private String number;
    private Company company;
    private LocalDate date;
    private Employee expeditor;
    private Vehicle vehicle;
    private TripStatus status;
    private LocalDateTime startedAt;
    private LocalDateTime closedAt;
    private List<Order> orders = new ArrayList<>();
    private List<Payment> payments = new ArrayList<>();
    private List<ProductReturn> returns = new ArrayList<>();
    /** Приём кассы: пересчитано наличных; null — ещё не пересчитали. */
    private Long cashCounted;
    private boolean kaspiChecked;
    private boolean goodsChecked;
    private String acceptedBy;

    private long sum(PaymentMethod m) {
        return payments.stream().filter(p -> p.getMethod() == m).mapToLong(Payment::getAmount).sum();
    }

    public long getCash() {
        return sum(PaymentMethod.CASH);
    }

    public long getKaspi() {
        return sum(PaymentMethod.KASPI);
    }

    public long getCredit() {
        return orders.stream().filter(o -> o.getStatus().delivered() && o.getPayment() == PaymentMethod.CREDIT)
                .mapToLong(o -> o.getDeliveredTotal()).sum();
    }

    public long getOldDebtCollected() {
        return payments.stream().filter(Payment::isOldDebt).mapToLong(Payment::getAmount).sum();
    }

    public long getLoadedTotal() {
        return orders.stream().mapToLong(Order::getTotal).sum();
    }

    public long getDeliveredTotal() {
        return orders.stream().mapToLong(Order::getDeliveredTotal).sum();
    }

    public long getReturnsTotal() {
        return returns.stream().mapToLong(ProductReturn::getTotal).sum();
    }

    public int getReturnsQty() {
        return returns.stream().mapToInt(ProductReturn::getQty).sum();
    }

    public int getStops() {
        return orders.size();
    }

    public int getDoneStops() {
        return (int) orders.stream().filter(o -> o.getStatus().delivered() || o.getStatus() == OrderStatus.REFUSED).count();
    }

    public int getProgress() {
        return orders.isEmpty() ? 0 : getDoneStops() * 100 / orders.size();
    }

    /** Невыданный товар (штук), который возвращается на основной склад. */
    public int getUndeliveredQty() {
        int n = 0;
        for (Order o : orders) {
            for (OrderLine l : o.getLines()) {
                if (o.getStatus() == OrderStatus.REFUSED) n += l.getQty();
                else if (l.getDelivered() != null) n += l.getQty() - l.getDelivered();
            }
        }
        return n;
    }

    /** Разница кассы: пересчитано − ожидается; минус — недостача. */
    public Long getCashDiff() {
        return cashCounted == null ? null : cashCounted - getCash();
    }
}
