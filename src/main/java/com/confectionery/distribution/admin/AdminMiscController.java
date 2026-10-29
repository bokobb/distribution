package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Role;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

/** Начальная страница и переключатели владельца: компания в шапке и «Смотреть как». */
@Controller
@RequiredArgsConstructor
public class AdminMiscController {

    private final AdminContext ctx;
    private final com.confectionery.distribution.repository.OrderRepository orders;

    @GetMapping("/")
    public String root() {
        return "redirect:/admin";
    }

    @GetMapping({"/admin", "/admin/"})
    public String home(HttpSession session) {
        return "redirect:" + AdminSections.home(ctx.viewer(session).role()).href();
    }

    @GetMapping("/admin/scope")
    public String scope(@RequestParam String company, @RequestParam(required = false) String back, HttpSession session) {
        Viewer v = ctx.viewer(session);
        if (v.owner()) {
            ctx.setCompany(session, "all".equals(company) ? null : parseId(company));
        }
        return "redirect:" + AdminPage.back(back, "/admin/dashboard");
    }

    /**
     * Поиск из шапки: номер заказа целиком (З-281026-1, С-1042) — сразу заказ; иначе — магазины по названию, адресу
     * или телефону, а если таких нет — заказы по тому же тексту.
     */
    @GetMapping("/admin/find")
    public String find(@RequestParam(required = false) String q) {
        String text = q == null ? "" : q.strip();
        if (text.isEmpty()) return "redirect:/admin";
        var order = orders.findFirstByNumberIgnoreCase(text);
        if (order.isPresent()) return "redirect:/admin/orders/" + order.get().getId();
        String enc = java.net.URLEncoder.encode(text, java.nio.charset.StandardCharsets.UTF_8);
        if (text.matches("(?iu)[a-zа-я]{1,2}-?\\d.*")) return "redirect:/admin/orders?day=all&q=" + enc;
        return "redirect:/admin/outlets?q=" + enc;
    }

    @GetMapping("/admin/as")
    public String as(@RequestParam Role role, @RequestParam(required = false) String back, HttpSession session) {
        if (!ctx.viewer(session).owner() || !role.webAdmin()) return "redirect:/admin";
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
