package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Outlet;
import lombok.Getter;
import lombok.Setter;

/** Форма магазина. Числа — строкой: при ошибке форма возвращается с тем, что ввели. */
@Getter
@Setter
public class OutletForm {
    private Long id;
    private String name;
    private String legal;
    private String bin;
    private String owner;
    private String phone;
    private String address;
    private Long agentId;
    private Long regionId;
    private Long priceTypeId;
    private String creditLimit;
    private String paymentDays;
    private String lat;
    private String lng;

    public static OutletForm of(Outlet o) {
        OutletForm f = new OutletForm();
        f.id = o.getId();
        f.name = o.getName();
        f.legal = o.getLegal();
        f.bin = o.getBin();
        f.owner = o.getOwner();
        f.phone = o.getPhone();
        f.address = o.getAddress();
        f.agentId = o.getAgent() == null ? null : o.getAgent().getId();
        f.regionId = o.getRegion() == null ? null : o.getRegion().getId();
        f.priceTypeId = o.getPriceType() == null ? null : o.getPriceType().getId();
        f.creditLimit = String.valueOf(o.getCreditLimit());
        f.paymentDays = String.valueOf(o.getPaymentDays());
        f.lat = o.getLat() == null ? null : o.getLat().toString();
        f.lng = o.getLng() == null ? null : o.getLng().toString();
        return f;
    }
}
