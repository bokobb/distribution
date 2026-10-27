package com.confectionery.distribution.service;

import lombok.Getter;
import lombok.Setter;

/** Новая компания (владелец): название, директор с телефоном для входа, клиент в CRM. */
@Getter
@Setter
public class CompanyForm {
    private String name;
    private String director;
    private String phone;
    private String crmClient;
}
