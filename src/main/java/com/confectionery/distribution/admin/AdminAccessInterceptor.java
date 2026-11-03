package com.confectionery.distribution.admin;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.HandlerMapping;

import java.util.Set;

/**
 * Раздел /admin/{key}/… открывается, только если он виден роли; иначе — на первый доступный раздел
 * со всплывающей строкой. Изменяющие действия «Компаний», «Настроек», «Сотрудников» дополнительно проверяют
 * роль сами ({@link AdminContext#require}).
 *
 * <p>Раздел берётся из шаблона адреса, на который Spring уже сопоставил запрос (/admin/staff/{id}), а не из
 * «сырого» адреса: до 03.11.2026 читался getRequestURI, и адрес с закодированной буквой (%73 вместо s)
 * не узнавался как раздел и пропускался, хотя открывал ту же страницу (аудит). Неизвестный ключ под /admin,
 * кроме служебных адресов, не пропускается.</p>
 */
@Component
@RequiredArgsConstructor
public class AdminAccessInterceptor implements HandlerInterceptor {

    /** Служебные адреса без своего раздела: компания в шапке, поиск, «Смотреть как» (проверяют сами). */
    static final Set<String> SERVICE = Set.of("scope", "find", "as");

    private final AdminContext ctx;

    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) throws Exception {
        String key = sectionKey(req);
        if (key == null || SERVICE.contains(key)) return true; // /admin, служебные
        Viewer v = ctx.viewer(req.getSession());
        AdminSections.Section s = AdminSections.byKey(key);
        if (s != null && s.visibleTo(v.role())) return true;
        if (s != null) ctx.toast(req.getSession(), "Раздел «" + s.title() + "» недоступен роли «" + v.role().getLabel() + "»");
        res.sendRedirect(req.getContextPath() + AdminSections.home(v.role()).href());
        return false;
    }

    /** Второй сегмент после /admin: из шаблона сопоставленного адреса, иначе из раскодированного пути. */
    static String sectionKey(HttpServletRequest req) {
        String path = req.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE) instanceof String p ? p : req.getServletPath();
        if (path == null) return null;
        String[] parts = path.split("/");
        return parts.length < 3 || parts[2].isEmpty() ? null : parts[2];
    }
}
