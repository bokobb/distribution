package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Role;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

/** Вход в админку и служебные переключатели: компания (владелец) и «Смотреть как» (заглушка входа). */
@Controller
@RequiredArgsConstructor
public class AdminMiscController {

    private final AdminContext ctx;

    @GetMapping({"/", "/admin", "/admin/"})
    public String home(HttpSession session) {
        return "redirect:" + AdminSections.home(ctx.viewer(session).role()).href();
    }

    @GetMapping("/admin/scope")
    public String scope(@RequestParam String company, @RequestParam(required = false) String back, HttpSession session) {
        Viewer v = ctx.viewer(session);
        if (v.isSuper()) {
            ctx.setCompany(session, "all".equals(company) ? null : parseId(company));
        }
        return "redirect:" + AdminPage.back(back, "/admin/dashboard");
    }

    @GetMapping("/admin/as")
    public String as(@RequestParam Role role, @RequestParam(required = false) String back, HttpSession session) {
        if (!role.webAdmin()) return "redirect:/admin";
        ctx.setRole(session, role);
        ctx.toast(session, "Смотрите админку как: " + role.getLabel());
        String target = AdminPage.back(back, "/admin");
        String key = target.split("/").length > 2 ? target.split("/")[2] : "";
        AdminSections.Section s = AdminSections.byKey(key);
        return "redirect:" + (s != null && s.visibleTo(role) ? target : AdminSections.home(role).href());
    }

    private static Long parseId(String s) {
        try {
            return Long.valueOf(s);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
