package com.confectionery.distribution.security;

import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

/** Ответ-ошибка приложению до контроллеров (фильтры безопасности): {"message": "…"} — текст для человека. */
public final class ApiErrors {

    private ApiErrors() {
    }

    public static void write(HttpServletResponse res, int status, String message) throws IOException {
        res.setStatus(status);
        res.setContentType("application/json");
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        res.getWriter().write("{\"message\":\"" + message.replace("\\", "\\\\").replace("\"", "\\\"") + "\"}");
    }
}
