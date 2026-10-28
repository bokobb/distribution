package com.confectionery.distribution.security;

import com.confectionery.distribution.tenant.TenantContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Запросы приложения (/api/mobile/**) с «Authorization: Bearer JWT». Сотрудник, роль и компания читаются из базы
 * на каждом запросе: отключённый или сменивший роль теряет доступ сразу, а не через 12 часов. Компания попадает
 * в TenantContext — Hibernate покажет только её записи. Пароль временный — открыта только его смена.
 * Без JWT или с негодным запрос идёт дальше без входа: закрытый адрес ответит 401 (SecurityConfig).
 */
public class MobileAuthFilter extends OncePerRequestFilter {

    public static final String PASSWORD_PATH = "/api/mobile/auth/password";

    private final JwtService jwt;
    private final MobileAccounts accounts;

    public MobileAuthFilter(JwtService jwt, MobileAccounts accounts) {
        this.jwt = jwt;
        this.accounts = accounts;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String header = req.getHeader(HttpHeaders.AUTHORIZATION);
        MobileUser user = header == null || !header.startsWith("Bearer ") ? null
                : jwt.userId(header.substring(7).strip()).flatMap(accounts::active).orElse(null);
        if (user == null) {
            chain.doFilter(req, res);
            return;
        }
        String path = req.getRequestURI().substring(req.getContextPath().length());
        if (user.mustChangePassword() && !path.equals(PASSWORD_PATH)) {
            ApiErrors.write(res, HttpServletResponse.SC_FORBIDDEN, "Сначала смените временный пароль");
            return;
        }
        SecurityContext ctx = SecurityContextHolder.createEmptyContext();
        ctx.setAuthentication(new UsernamePasswordAuthenticationToken(user, null,
                List.of(new SimpleGrantedAuthority("ROLE_" + user.role().name()))));
        SecurityContextHolder.setContext(ctx);
        TenantContext.set(user.companyId());
        try {
            chain.doFilter(req, res);
        } finally {
            TenantContext.clear();
            SecurityContextHolder.clearContext();
        }
    }
}
