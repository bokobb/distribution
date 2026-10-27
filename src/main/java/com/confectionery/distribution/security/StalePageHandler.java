package com.confectionery.distribution.security;

import com.confectionery.distribution.admin.AdminContext;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.security.web.csrf.CsrfException;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Форма отправлена со страницы, открытой до перезапуска сервера или до конца сессии: ключ формы (CSRF)
 * уже не действует. Действие не выполняется, а человек возвращается туда, где можно повторить, —
 * без служебной страницы ошибки.
 */
@Component
@RequiredArgsConstructor
public class StalePageHandler implements AccessDeniedHandler {

    private final AdminContext ctx;

    @Override
    public void handle(HttpServletRequest req, HttpServletResponse res, AccessDeniedException e) throws IOException {
        if (!(e instanceof CsrfException)) {
            res.sendError(HttpServletResponse.SC_FORBIDDEN);
            return;
        }
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof AdminUser)) {
            res.sendRedirect(req.getContextPath() + "/login?expired");
            return;
        }
        ctx.toast(req.getSession(), "Страница устарела — действие не выполнено. Повторите его ещё раз");
        res.sendRedirect(req.getContextPath() + "/admin");
    }
}
