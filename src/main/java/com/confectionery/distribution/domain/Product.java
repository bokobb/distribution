package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

/** Товар в каталоге компании. Свой прайс у каждой компании. */
@Getter
@Setter
@Accessors(chain = true)
public class Product {
    private Long id;
    private Company company;
    private String name;
    private String category;
    private String unit = "шт";
    private int perBox;
    private String barcode;
    /** Код товара в CRM производства — для автоприхода. null — товар другого поставщика. */
    private String crmCode;
    private long retail;
    private long wholesale;
    private boolean active = true;

    public long price(String priceType) {
        return "Розница".equals(priceType) ? retail : wholesale;
    }
}
