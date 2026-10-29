package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.AssignService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.OutletService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.List;

/** «Закрепление магазинов»: магазин закрепляется за торговым без дней и порядка обхода. */
@Controller
@RequiredArgsConstructor
public class AdminAssignController {

    private final AdminContext ctx;
    private final AssignService assign;
    private final OutletService outlets;
    private final Fmt fmt;
    private final tools.jackson.databind.ObjectMapper json;

    /** agent — id торгового или «none» — магазины без торгового. */
    @GetMapping("/admin/assign")
    public String page(@RequestParam(required = false) String agent, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "assign", "Закрепление магазинов",
                "вместо маршрутов: у магазина есть свой торговый, день и порядок обхода не задаются");
        if (v.isAll()) return "admin/assign";
        boolean none = "none".equals(agent);
        Long agentId = none || agent == null ? null : parseId(agent);
        AssignService.Page p = assign.page(v.companyId(), agentId, none);
        model.addAttribute("p", p);
        model.addAttribute("none", none);
        model.addAttribute("shopsJson", json.writeValueAsString(p.shops().stream().filter(s -> s.lat() != null && s.lng() != null)
                .map(s -> java.util.Map.of("id", s.id(), "name", s.name(), "lat", s.lat(), "lng", s.lng(),
                        "agent", s.agentId() == null ? 0L : s.agentId()))
                .toList()));
        return "admin/assign";
    }

    @PostMapping("/admin/assign")
    public String save(@RequestParam(name = "ids", required = false) List<Long> ids, @RequestParam String to,
                       @RequestParam(required = false) String back, HttpSession session) {
        Viewer v = ctx.viewer(session);
        if (ids == null || ids.isEmpty()) {
            ctx.toast(session, "Отметьте магазины в списке или на карте");
        } else {
            try {
                Long agentId = "none".equals(to) ? null : parseId(to);
                int n = outlets.assign(ids, agentId);
                ctx.toast(session, fmt.plural(n, "магазин", "магазина", "магазинов")
                        + (agentId == null ? " — без торгового" : " — закреплено"));
                if (agentId != null) return "redirect:/admin/assign?agent=" + agentId;
            } catch (FormException e) {
                ctx.toast(session, e.getMessage());
            }
        }
        return "redirect:" + AdminPage.back(back, "/admin/assign");
    }

    private static Long parseId(String s) {
        try {
            return Long.valueOf(s);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
