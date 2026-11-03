package com.confectionery.distribution.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpMethod;
import org.springframework.security.web.servlet.util.matcher.PathPatternRequestMatcher;
import org.springframework.security.web.util.matcher.RequestMatcher;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Вход в веб-админку (POST /login) во время паузы после неверных паролей пароль даже не проверяет — сразу назад на
 * страницу входа с временем ожидания (счёт общий с приложением, см. {@link LoginAttempts}; аудит 03.11.2026).
 */
public class LoginPauseFilter extends OncePerRequestFilter {

    /** Тот же способ сопоставления, что у входа Spring Security, — иначе «/log%69n» прошёл бы мимо паузы. */
    private static final RequestMatcher LOGIN = PathPatternRequestMatcher.withDefaults().matcher(HttpMethod.POST, "/login");

    private final LoginAttempts attempts;

    public LoginPauseFilter(LoginAttempts attempts) {
        this.attempts = attempts;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        return !LOGIN.matches(req);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        long wait = attempts.secondsLeft(LoginAttempts.key(req.getParameter("username")));
        if (wait > 0) {
            res.sendRedirect(req.getContextPath() + "/login?wait=" + wait);
            return;
        }
        chain.doFilter(req, res);
    }
}
