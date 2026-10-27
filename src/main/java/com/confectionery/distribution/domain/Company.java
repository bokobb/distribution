package com.confectionery.distribution.domain;

import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.Accessors;

import java.time.LocalDateTime;

/**
 * Компания дистрибуции: собственная доставка производства или склад-дилер. Все данные (магазины,
 * заказы, касса) принадлежат одной компании; владелец (SUPER_ADMIN) видит все.
 */
@Entity
@Table(name = "companies")
@Getter
@Setter
@Accessors(chain = true)
public class Company extends BaseEntity {
    private String name;
    /** ФИО директора для списков; сам директор — сотрудник с ролью DIRECTOR. */
    private String director;
    private String phone;
    /** Клиент этой компании в CRM производства — для автоприхода отгрузок. null — своя доставка. */
    private String crmClient;
    /** Своя доставка производства. */
    private boolean own;
    private boolean active = true;
    private LocalDateTime createdAt;
}
