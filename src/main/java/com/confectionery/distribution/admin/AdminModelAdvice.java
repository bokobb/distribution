package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.CompanyService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ModelAttribute;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/** Общее для всех страниц админки: кто смотрит, меню по роли, список компаний, значки, всплывающая строка. */
@ControllerAdvice(basePackageClasses = AdminModelAdvice.class)
@RequiredArgsConstructor
public class AdminModelAdvice {

    private final AdminContext ctx;
    private final CompanyService companies;
    private final Clock clock;
    private final AdminIcons icons;
    private Map<String, String> i20, i16;

    @ModelAttribute
    public void common(Model model, HttpSession session, jakarta.servlet.http.HttpServletRequest request) {
        Viewer v = ctx.viewer(session);
        // текущий адрес — для «вернуться сюда» после смены компании или роли (#request в Thymeleaf 3.1 закрыт)
        String q = request.getQueryString();
        model.addAttribute("here", request.getRequestURI() + (q == null ? "" : "?" + q));
        model.addAttribute("v", v);
        model.addAttribute("menu", AdminSections.menu(v.role()));
        // список компаний — только владельцу, остальным — их компания
        model.addAttribute("companies", v.owner() ? companies.all() : v.company() == null ? List.of() : List.of(v.company()));
        model.addAttribute("roles", java.util.Arrays.stream(com.confectionery.distribution.domain.Role.values())
                .filter(com.confectionery.distribution.domain.Role::webAdmin).toList());
        model.addAttribute("today", LocalDate.now(clock));
        if (i20 == null) {
            i20 = icons.all(20);
            i16 = icons.all(16);
        }
        model.addAttribute("i", i20);
        model.addAttribute("i16", i16);
        Object toast = session.getAttribute(AdminContext.TOAST);
        if (toast != null) {
            session.removeAttribute(AdminContext.TOAST);
            model.addAttribute("toast", toast.toString());
        }
    }
}
