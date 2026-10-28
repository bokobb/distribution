package com.confectionery.distribution.config;

import com.confectionery.distribution.security.AdminUserService;
import com.confectionery.distribution.security.ApiErrors;
import com.confectionery.distribution.security.JwtService;
import com.confectionery.distribution.security.MobileAccounts;
import com.confectionery.distribution.security.MobileAuthFilter;
import com.confectionery.distribution.security.StalePageHandler;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AccountStatusUserDetailsChecker;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AnonymousAuthenticationFilter;

/**
 * Вход в веб-админку: страница /login, телефон или логин + пароль (BCrypt), сессия. Без входа открыты
 * только страница входа и оформление. Приложение агента и экспедитора — /api/mobile, по JWT, без сессии и
 * cookie (MobileAuthFilter); остальной /api закрыт.
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

    /**
     * Приложение: открыты только вход, продление по ключу устройства и выход; остальное — торговому агенту и
     * экспедитору с JWT. Ошибки — JSON с текстом для человека.
     */
    @Bean
    @Order(1)
    public SecurityFilterChain mobileApi(HttpSecurity http, JwtService jwt, MobileAccounts accounts) throws Exception {
        http.securityMatcher("/api/mobile/**")
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(a -> a
                        .requestMatchers(HttpMethod.POST, "/api/mobile/auth/login", "/api/mobile/auth/refresh",
                                "/api/mobile/auth/logout").permitAll()
                        .requestMatchers("/api/mobile/agent/**").hasRole("AGENT")
                        .requestMatchers("/api/mobile/expeditor/**").hasRole("EXPEDITOR")
                        .anyRequest().hasAnyRole("AGENT", "EXPEDITOR"))
                .addFilterBefore(new MobileAuthFilter(jwt, accounts), AnonymousAuthenticationFilter.class)
                .exceptionHandling(e -> e
                        .authenticationEntryPoint((req, res, ex) ->
                                ApiErrors.write(res, HttpServletResponse.SC_UNAUTHORIZED, "Войдите заново"))
                        .accessDeniedHandler((req, res, ex) ->
                                ApiErrors.write(res, HttpServletResponse.SC_FORBIDDEN, "Нет доступа")));
        return http.build();
    }

    @Bean
    @Order(2)
    public SecurityFilterChain web(HttpSecurity http, StalePageHandler stalePage) throws Exception {
        http.authorizeHttpRequests(a -> a
                        .requestMatchers("/login", "/admin/assets/**", "/error", "/favicon.ico").permitAll()
                        .requestMatchers("/api/**").denyAll()
                        .anyRequest().authenticated())
                .formLogin(f -> f.loginPage("/login").defaultSuccessUrl("/admin", false).failureUrl("/login?error"))
                .logout(l -> l.logoutUrl("/logout").logoutSuccessUrl("/login?logout"))
                .exceptionHandling(e -> e.accessDeniedHandler(stalePage));
        return http.build();
    }
}
