package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.ApprovalService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.SettingsService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.Set;

/** «Разрешения»: заказы сверх правил, недоплаты и новые магазины — решение одной кнопкой и «Вернуть». */
@Controller
@RequiredArgsConstructor
public class AdminApprovalController {

    private static final Set<String> FILTERS = Set.of("all", "money", "shops");

    private final AdminContext ctx;
    private final ApprovalService approvals;
    private final SettingsService settings;

    /** f — all, money (заказы и долги) или shops (новые магазины). */
    @GetMapping("/admin/approvals")
    public String page(@RequestParam(defaultValue = "all") String f, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "approvals", "Разрешения", "заказы сверх правил и новые магазины ждут решения");
        model.addAttribute("p", approvals.page(v.companyId(), v.role()));
        model.addAttribute("f", FILTERS.contains(f) ? f : "all");
        model.addAttribute("st", settings.of(v.companyId()));
        return "admin/approvals";
    }

    @PostMapping("/admin/approvals/decide")
    public String decide(@RequestParam String key, @RequestParam String code, @RequestParam(defaultValue = "all") String f,
                         HttpSession session) {
        Viewer v = ctx.viewer(session);
        try {
            ctx.toast(session, approvals.decide(key, code, v.actor(), v.role()));
        } catch (FormException e) {
            ctx.toast(session, e.getMessage());
        }
        return "redirect:/admin/approvals?f=" + (FILTERS.contains(f) ? f : "all");
    }

    @PostMapping("/admin/approvals/{id}/undo")
    public String undo(@PathVariable Long id, HttpSession session) {
        try {
            ctx.toast(session, approvals.undo(id, ctx.viewer(session).actor()));
        } catch (FormException e) {
            ctx.toast(session, e.getMessage());
        }
        return "redirect:/admin/approvals";
    }
}
