package com.confectionery.distribution.domain;

import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

/**
 * Компания дистрибуции: собственная доставка производства или склад-дилер. Все данные (магазины,
 * заказы, касса) принадлежат одной компании; владелец (SUPER_ADMIN) видит все.
 */
@Getter
@Setter
@Accessors(chain = true)
public class Company {
    private Long id;
    private String name;
    private String director;
    private String phone;
    /** Клиент этой компании в CRM производства — для автоприхода отгрузок. null — своя доставка. */
    private String crmClient;
    /** Своя доставка производства. */
    private boolean own;
    private boolean active = true;
}
