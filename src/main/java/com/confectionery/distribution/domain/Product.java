package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

/** Товар в каталоге компании. Свой прайс у каждой компании. */
@Entity
@Table(name = "products")
@Getter
@Setter
@Accessors(chain = true)
public class Product extends CompanyEntity {
    private String name;
    private String category;
    private String unit = "шт";
    private int perBox = 1;
    private String barcode;
    /** Код товара в CRM производства — для автоприхода. null — товар другого поставщика. */
    private String crmCode;
    private boolean active = true;
    /** Цена CRM за штуку — из последнего выданного заказа CRM; null — ещё не приходил или товар не из CRM. */
    private Long crmPrice;
    private java.time.LocalDateTime crmPriceAt;

    /** Цены на сегодня (заполняет CatalogService из таблицы prices). */
    @Transient
    private long wholesale;
    @Transient
    private long retail;

    /** Наценка опта над ценой CRM, %; null — цены CRM нет. */
    public Integer getMarkup() {
        return crmPrice == null || crmPrice == 0 || wholesale == 0 ? null : (int) Math.round((wholesale - crmPrice) * 100.0 / crmPrice);
    }

    public long price(PriceKind kind) {
        return kind == PriceKind.RETAIL ? retail : wholesale;
    }
}
