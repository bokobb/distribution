package com.confectionery.distribution.admin;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * Раздел /admin/{key}/… открывается, только если он виден роли; иначе — на первый доступный раздел
 * со всплывающей строкой. Сами страницы права не проверяют.
 */
@Component
@RequiredArgsConstructor
public class AdminAccessInterceptor implements HandlerInterceptor {

    private final AdminContext ctx;

    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) throws Exception {
        String path = req.getRequestURI().substring(req.getContextPath().length());
        String[] parts = path.split("/");
        if (parts.length < 3) return true; // /admin
        AdminSections.Section s = AdminSections.byKey(parts[2]);
        if (s == null) return true; // служебные адреса: scope, as
        Viewer v = ctx.viewer(req.getSession());
        if (s.visibleTo(v.role())) return true;
        ctx.toast(req.getSession(), "Раздел «" + s.title() + "» недоступен роли «" + v.role().getLabel() + "»");
        res.sendRedirect(req.getContextPath() + AdminSections.home(v.role()).href());
        return false;
    }
}
