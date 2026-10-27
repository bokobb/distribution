package com.confectionery.distribution.config;

import com.confectionery.distribution.security.AdminUserService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.authentication.AccountStatusUserDetailsChecker;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Вход в веб-админку: страница /login, телефон или логин + пароль (BCrypt), сессия. Без входа открыты
 * только страница входа и оформление. /api закрыт до приложения агентов (там будет JWT).
 */
@Configuration
public class SecurityConfig {

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /**
     * Отключён ли сотрудник, проверяется только после верного пароля: по ответу на неверный пароль
     * нельзя узнать, есть ли такой сотрудник и открыт ли ему вход.
     */
    @Bean
    public DaoAuthenticationProvider authenticationProvider(AdminUserService users, PasswordEncoder encoder) {
        DaoAuthenticationProvider p = new DaoAuthenticationProvider(users);
        p.setPasswordEncoder(encoder);
        p.setPreAuthenticationChecks(u -> {
        });
        p.setPostAuthenticationChecks(new AccountStatusUserDetailsChecker());
        return p;
    }

    @Bean
    public SecurityFilterChain web(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests(a -> a
                        .requestMatchers("/login", "/admin/assets/**", "/error").permitAll()
                        .requestMatchers("/api/**").denyAll()
                        .anyRequest().authenticated())
                .formLogin(f -> f.loginPage("/login").defaultSuccessUrl("/admin", false).failureUrl("/login?error"))
                .logout(l -> l.logoutUrl("/logout").logoutSuccessUrl("/login?logout"));
        return http.build();
    }
}
