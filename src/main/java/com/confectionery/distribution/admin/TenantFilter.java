package com.confectionery.distribution.admin;

import com.confectionery.distribution.tenant.TenantContext;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * В начале запроса к админке: кто смотрит и какая компания открыта. Компания попадает в
 * {@link TenantContext} — и Hibernate показывает только её записи. Владелец в «Все компании» и в
 * разделе «Компании» работает без фильтра.
 */
@Component
@RequiredArgsConstructor
public class TenantFilter extends OncePerRequestFilter {

    private final AdminContext ctx;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        String path = req.getRequestURI().substring(req.getContextPath().length());
        return !path.startsWith("/admin") || path.startsWith("/admin/assets/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        Viewer v = ctx.resolve(req.getSession());
        req.setAttribute(AdminContext.VIEWER, v);
        String path = req.getRequestURI().substring(req.getContextPath().length());
        boolean companies = v.owner() && v.isSuper() && path.startsWith("/admin/companies");
        TenantContext.set(v.isAll() || companies ? TenantContext.ROOT : v.companyId());
        try {
            chain.doFilter(req, res);
        } finally {
            TenantContext.clear();
        }
    }
}
