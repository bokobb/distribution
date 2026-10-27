package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface EmployeeRepository extends JpaRepository<Employee, Long> {
    Optional<Employee> findByPhone(String phone);

    Optional<Employee> findByLogin(String login);

    List<Employee> findByRoleOrderByNameAsc(Role role);

    List<Employee> findByCompanyIdIsNotNullOrderByNameAsc();

    boolean existsByRole(Role role);

    Optional<Employee> findFirstByCompanyIdAndRoleOrderByIdAsc(Long companyId, Role role);
}
