package com.confectionery.distribution.security;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.service.Phones;
import com.confectionery.distribution.tenant.TenantContext;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Locale;
import java.util.Optional;

/**
 * Вход в веб-админку: телефон в любом виде («8 701 …», «+7 (701) …») или логин. Агент и экспедитор
 * в веб не входят (у них приложение), отключённый сотрудник — никуда.
 */
@Service
@RequiredArgsConstructor
public class AdminUserService implements UserDetailsService {

    private final EmployeeRepository employees;

    @Override
    public UserDetails loadUserByUsername(String input) {
        // до входа компании нет — сотрудника ищем по всем компаниям
        Employee e = TenantContext.asRoot(() -> find(input)).orElseThrow(() -> new UsernameNotFoundException("Нет такого сотрудника"));
        return new AdminUser(e.getId(), e.getPhone(), e.getPasswordHash() == null ? "" : e.getPasswordHash(),
                e.isActive() && e.getRole().webAdmin(), List.of(new SimpleGrantedAuthority("ROLE_" + e.getRole().name())));
    }

    private Optional<Employee> find(String input) {
        if (input == null || input.isBlank()) return Optional.empty();
        String phone = Phones.normalize(input);
        if (phone != null) return employees.findByPhone(phone);
        return employees.findByLogin(input.strip().toLowerCase(Locale.ROOT));
    }
}
