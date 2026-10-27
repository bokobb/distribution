package com.confectionery.distribution.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
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

/** Приход товара на основной склад компании. */
@Entity
@Table(name = "receipts")
@Getter
@Setter
@Accessors(chain = true)
public class Receipt extends CompanyEntity {
    private String number;
    @Enumerated(EnumType.STRING)
    private ReceiptSource source;
    @Enumerated(EnumType.STRING)
    private ReceiptStatus status;
    @Column(name = "doc_date")
    private LocalDate date;
    /** Документ-основание: «Отгрузка CRM №…» или накладная поставщика. */
    private String basis;
    private String supplier;
    @ManyToOne(fetch = FetchType.LAZY)
    private Warehouse warehouse;
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "confirmed_by")
    private Employee confirmedByUser;
    private LocalDateTime confirmedAt;
    private LocalDateTime createdAt;
    @OneToMany(mappedBy = "receipt", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("id")
    private List<ReceiptLine> lines = new ArrayList<>();

    public Receipt addLine(ReceiptLine line) {
        line.setReceipt(this);
        line.setCompany(getCompany());
        lines.add(line);
        return this;
    }

    public int getQty() {
        return lines.stream().mapToInt(ReceiptLine::getExpected).sum();
    }

    /** Кто принял — имя для страницы. */
    public String getConfirmedBy() {
        return confirmedByUser == null ? null : confirmedByUser.getName();
    }
}
