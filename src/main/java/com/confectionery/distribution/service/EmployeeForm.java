package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import lombok.Getter;
import lombok.Setter;

/** Форма сотрудника: ФИО, роль, телефон для входа и необязательный логин. */
@Getter
@Setter
public class EmployeeForm {
    private Long id;
    private String name;
    private Role role = Role.AGENT;
    private String phone;
    private String login;

    public static EmployeeForm of(Employee e) {
        EmployeeForm f = new EmployeeForm();
        f.id = e.getId();
        f.name = e.getName();
        f.role = e.getRole();
        f.phone = Phones.format(e.getPhone());
        f.login = e.getLogin();
        return f;
    }
}
