package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.OutletStatus;
import com.confectionery.distribution.service.OutletService;
import com.confectionery.distribution.service.RouteService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.*;

@Controller
@RequiredArgsConstructor
public class AdminOutletController {

    private final AdminContext ctx;
    private final OutletService outlets;
    private final RouteService routes;
    private final Fmt fmt;

    @GetMapping("/admin/outlets")
    public String list(@RequestParam(required = false) OutletStatus status,
                       @RequestParam(required = false) Long region,
                       @RequestParam(required = false) String q,
                       Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Outlet> all = outlets.list(v.companyId());
        Map<OutletStatus, Long> counts = new EnumMap<>(OutletStatus.class);
        for (Outlet o : all) counts.merge(o.getStatus(), 1L, Long::sum);
        String needle = q == null ? "" : q.trim().toLowerCase(Locale.ROOT);
        List<Outlet> list = all.stream()
                .filter(o -> status == null || o.getStatus() == status)
                .filter(o -> region == null || (o.getRegion() != null && region.equals(o.getRegion().getId())))
                .filter(o -> needle.isEmpty() || (o.getName() + " " + o.getOwner() + " " + o.getPhone() + " " + o.getAddress())
                        .toLowerCase(Locale.ROOT).contains(needle))
                .sorted(Comparator.comparing(Outlet::getName)).toList();
        AdminPage.head(model, "outlets", "Магазины", v.scopeName() + " · " + fmt.plural(all.size(), "точка", "точки", "точек"));
        model.addAttribute("outlets", list);
        model.addAttribute("counts", counts);
        model.addAttribute("total", all.size());
        model.addAttribute("statuses", OutletStatus.values());
        model.addAttribute("status", status);
        model.addAttribute("regions", routes.regions());
        model.addAttribute("region", region);
        model.addAttribute("q", q);
        return "admin/outlets/list";
    }

    @GetMapping("/admin/outlets/{id}")
    public String view(@PathVariable Long id, Model model, HttpSession session) {
        Outlet o = outlets.get(id);
        AdminPage.head(model, "outlets", o.getName(), o.getLegal() + " · " + o.getAddress());
        model.addAttribute("o", o);
        model.addAttribute("orders", outlets.ordersOf(o));
        model.addAttribute("payments", outlets.paymentsOf(o));
        model.addAttribute("returns", outlets.returnsOf(o));
        return "admin/outlets/view";
    }

    @GetMapping("/admin/outlets/new")
    public String create(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "outlets", "Новый магазин", v.scopeName());
        model.addAttribute("o", new Outlet().setCreditLimit(100_000).setPaymentDays(7));
        model.addAttribute("routes", routes.routes());
        return "admin/outlets/form";
    }

    @GetMapping("/admin/outlets/{id}/edit")
    public String edit(@PathVariable Long id, Model model, HttpSession session) {
        Outlet o = outlets.get(id);
        AdminPage.head(model, "outlets", "Изменить магазин", o.getName());
        model.addAttribute("o", o);
        model.addAttribute("routes", routes.routes());
        return "admin/outlets/form";
    }

    /** ЗАГЛУШКА: форма ничего не сохраняет, только показывает, что сохранение будет здесь. */
    @PostMapping("/admin/outlets/save")
    public String save(@RequestParam(required = false) Long id, @RequestParam String name, HttpSession session) {
        ctx.toast(session, "«" + name + "»: сохранение заработает на этапе 1 (сейчас данные — заглушки)");
        return "redirect:" + (id != null ? "/admin/outlets/" + id : "/admin/outlets");
    }

    @PostMapping("/admin/outlets/{id}/approve")
    public String approve(@PathVariable Long id, HttpSession session) {
        Outlet o = outlets.approve(id);
        ctx.toast(session, o.getName() + " — проверен, работает");
        return "redirect:/admin/outlets/" + id;
    }
}
