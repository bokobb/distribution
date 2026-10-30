package com.confectionery.distribution.domain;

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

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/** Рейс: машина + экспедитор на день, заказы по порядку точек. */
@Entity
@Table(name = "trips")
@Getter
@Setter
@Accessors(chain = true)
public class Trip extends CompanyEntity {
    private String number;
    @Column(name = "trip_date")
    private LocalDate date;
    @ManyToOne(fetch = FetchType.LAZY)
    private Employee expeditor;
    @ManyToOne(fetch = FetchType.LAZY)
    private Vehicle vehicle;
    @Enumerated(EnumType.STRING)
    private TripStatus status;
    private LocalDateTime startedAt;
    private LocalDateTime returnedAt;
    private LocalDateTime closedAt;
    /** Заказы рейса по порядку точек (getStops() — их число, для страниц). */
    @OneToMany(mappedBy = "trip")
    @OrderBy("position")
    private List<TripOrder> tripOrders = new ArrayList<>();
    @OneToMany(mappedBy = "trip")
    @OrderBy("at")
    private List<Payment> payments = new ArrayList<>();
    @OneToMany(mappedBy = "trip")
    @OrderBy("id")
    private List<ProductReturn> returns = new ArrayList<>();
    /** Приём кассы (не больше одного на рейс). */
    @OneToMany(mappedBy = "trip")
    private List<CashHandover> handovers = new ArrayList<>();

    /** Заказы по порядку точек. */
    public List<Order> getOrders() {
        return tripOrders.stream().map(TripOrder::getOrder).toList();
    }

    public CashHandover getHandover() {
        return handovers.isEmpty() ? null : handovers.get(0);
    }

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
        return getOrders().stream().filter(o -> o.getStatus().delivered() && o.getPayment() == PaymentMethod.CREDIT)
                .mapToLong(Order::getDeliveredTotal).sum();
    }

    public long getOldDebtCollected() {
        return payments.stream().filter(Payment::isOldDebt).mapToLong(Payment::getAmount).sum();
    }

    public long getLoadedTotal() {
        return getOrders().stream().mapToLong(Order::getTotal).sum();
    }

    public long getDeliveredTotal() {
        return getOrders().stream().mapToLong(Order::getDeliveredTotal).sum();
    }

    public long getReturnsTotal() {
        return returns.stream().mapToLong(ProductReturn::getTotal).sum();
    }

    public int getReturnsQty() {
        return returns.stream().mapToInt(ProductReturn::getQty).sum();
    }

    /** Выдано магазинам (целиком или частично) — без отказов. */
    public int getHanded() {
        return (int) getOrders().stream().filter(o -> o.getStatus().delivered()).count();
    }

    /** Из выданных — с подписью получателя или фото накладной. */
    public int getProofs() {
        return (int) getOrders().stream().filter(o -> o.getStatus().delivered() && o.getDelivery() != null && o.getDelivery().getProof() != null).count();
    }

    public int getStops() {
        return tripOrders.size();
    }

    public int getDoneStops() {
        return (int) getOrders().stream().filter(o -> o.getStatus().delivered() || o.getStatus() == OrderStatus.REFUSED).count();
    }

    /** Рейс не закрыт: касса и невыданный товар ещё у экспедитора. */
    public boolean isOpen() {
        return status != TripStatus.CLOSED;
    }

    /** Касса ждёт приёма: все точки пройдены (выдано или отказ) или рейс уже отмечен вернувшимся (старые рейсы). */
    public boolean isWaitingCash() {
        return status == TripStatus.RETURNED || isOpen() && !tripOrders.isEmpty() && getDoneStops() == tripOrders.size();
    }

    public int getProgress() {
        return tripOrders.isEmpty() ? 0 : getDoneStops() * 100 / tripOrders.size();
    }

    /** Невыданный товар (штук), который возвращается на основной склад. */
    public int getUndeliveredQty() {
        int n = 0;
        for (Order o : getOrders()) {
            for (OrderLine l : o.getLines()) {
                if (o.getStatus() == OrderStatus.REFUSED) n += l.getQty();
                else if (l.getDelivered() != null) n += l.getQty() - l.getDelivered();
            }
        }
        return n;
    }

    // приём кассы — из CashHandover

    /** Пересчитано наличных; null — ещё не пересчитали. */
    public Long getCashCounted() {
        CashHandover h = getHandover();
        return h == null ? null : h.getCountedCash();
    }

    public boolean isKaspiChecked() {
        CashHandover h = getHandover();
        return h != null && h.isKaspiChecked();
    }

    public boolean isGoodsChecked() {
        CashHandover h = getHandover();
        return h != null && h.isGoodsChecked();
    }

    /** Кто принял кассу — имя для страницы. */
    public String getAcceptedBy() {
        CashHandover h = getHandover();
        return h == null || h.getAcceptedBy() == null ? null : h.getAcceptedBy().getName();
    }

    /** Недостача больше допуска пересчитана, рейс ждёт решения директора. */
    public boolean isShortageWaiting() {
        CashHandover h = getHandover();
        return isOpen() && h != null && h.getCashDiff() != null && h.getCashDiff() < 0;
    }

    /** Что решили по недостаче; null — недостачи не было или ещё не решили. */
    public CashHandover getShortage() {
        CashHandover h = getHandover();
        return h == null || h.getShortageDecision() == null ? null : h;
    }

    /** Разница кассы: пересчитано − ожидается; минус — недостача. */
    public Long getCashDiff() {
        CashHandover h = getHandover();
        if (h == null || h.getCountedCash() == null) return null;
        return h.getCashDiff() != null ? h.getCashDiff() : h.getCountedCash() - getCash();
    }
}
