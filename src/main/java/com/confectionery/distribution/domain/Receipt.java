package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/** Приход товара на основной склад компании. */
@Getter
@Setter
@Accessors(chain = true)
public class Receipt {
    private Long id;
    private String number;
    private Company company;
    private ReceiptSource source;
    private ReceiptStatus status;
    private LocalDate date;
    /** Документ-основание: «Отгрузка CRM №…» или накладная поставщика. */
    private String basis;
    private String supplier;
    private String confirmedBy;
    private List<ReceiptLine> lines = new ArrayList<>();

    public int getQty() {
        return lines.stream().mapToInt(ReceiptLine::getExpected).sum();
    }
}
