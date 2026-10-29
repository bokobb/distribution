package com.confectionery.distribution.domain;

import jakarta.persistence.CascadeType;
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

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/** Выдача заказа экспедитором: полностью, частично или отказ магазина. */
@Entity
@Table(name = "deliveries")
@Getter
@Setter
@Accessors(chain = true)
public class Delivery extends CompanyEntity {
    private UUID uuid = UUID.randomUUID();
    @ManyToOne(fetch = FetchType.LAZY)
    private Order order;
    @ManyToOne(fetch = FetchType.LAZY)
    private Trip trip;
    @Enumerated(EnumType.STRING)
    private DeliveryStatus status;
    private LocalDateTime deliveredAt;
    @ManyToOne(fetch = FetchType.LAZY)
    private Employee expeditor;
    private String refuseReason;
    private Double lat;
    private Double lng;
    /** Подпись получателя (PNG) или фото накладной (JPEG) — путь в FileStore; null — не прислали. */
    private String proof;
    @OneToMany(mappedBy = "delivery", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("id")
    private List<DeliveryItem> items = new ArrayList<>();

    public Delivery addItem(DeliveryItem item) {
        item.setDelivery(this);
        item.setCompany(getCompany());
        items.add(item);
        return this;
    }

    /** Подтверждение — фото накладной, а не подпись на экране. */
    public boolean isProofPhoto() {
        return proof != null && proof.endsWith(".jpg");
    }

    public long getTotal() {
        return status == DeliveryStatus.REFUSED ? 0 : items.stream().mapToLong(DeliveryItem::getSum).sum();
    }
}
