package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.domain.Vehicle;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.repository.VehicleRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.Comparator;
import java.util.List;

/** Сотрудники компаний и машины. Владелец (без компании) в списки сотрудников не входит. */
@Service
@RequiredArgsConstructor
public class StaffService {

    private final EmployeeRepository employees;
    private final VehicleRepository vehicles;

    /** Сотрудники компании (с закреплёнными машинами); companyId = null — все видимые. */
    public List<Employee> employees(Long companyId) {
        List<Employee> list = employees.findByCompanyIdIsNotNullOrderByNameAsc().stream()
                .filter(e -> companyId == null || companyId.equals(e.getCompanyId())).toList();
        for (Vehicle v : vehicles.findAllByOrderByPlateAsc()) {
            if (v.getExpeditor() == null) continue;
            list.stream().filter(e -> e.getId().equals(v.getExpeditor().getId())).findFirst().ifPresent(e -> e.setVehicle(v));
        }
        return list;
    }

    public List<Employee> staff(Long companyId, Role role) {
        return employees(companyId).stream().filter(e -> e.getRole() == role).toList();
    }

    public List<Vehicle> vehicles(Long companyId) {
        return vehicles.findAllByOrderByPlateAsc().stream()
                .filter(v -> companyId == null || companyId.equals(v.getCompanyId()))
                .sorted(Comparator.comparing(Vehicle::getCompanyId).thenComparing(Vehicle::getPlate)).toList();
    }
}
