package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.service.OrderSearch;
import com.confectionery.distribution.service.OrderService;
import com.confectionery.distribution.service.RouteService;
import com.confectionery.distribution.service.StaffService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;

@Controller
@RequiredArgsConstructor
public class AdminOrderController {

    private final AdminContext ctx;
    private final OrderService orders;
    private final OrderSearch search;
    private final StaffService staff;
    private final RouteService routes;
    private final Fmt fmt;
    private final Clock clock;

    /** Пункт выпадающего фильтра: торговый, филиал, экспедитор. */
    public record Option(Long id, String name, boolean on) {
    }

    /**
     * Заказы с фильтрами. Дата доставки: day = today | tomorrow (завтра и позже) | all — быстрый выбор,
     * day = range — «с» и «по» из формы; без условий — завтра и позже, как на дашборде. Торговые и филиалы —
     * несколько сразу; экспедитор: пусто — любой, none — ещё не отгружены, id — его рейсы.
     */
    @GetMapping("/admin/orders")
    public String list(@RequestParam(required = false) String day,
                       @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                       @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                       @RequestParam(name = "agent", required = false) List<Long> agentIds,
                       @RequestParam(name = "region", required = false) List<Long> regionIds,
                       @RequestParam(required = false) String exp,
                       @RequestParam(required = false) OrderStatus status,
                       @RequestParam(required = false) String q,
                       @RequestParam(defaultValue = "1") int page,
                       @RequestParam(defaultValue = "" + OrderSearch.DEFAULT_SIZE) int size,
                       Model model, HttpSession session, HttpServletRequest request) {
        Viewer v = ctx.viewer(session);
        LocalDate today = LocalDate.now(clock);
        if (!"range".equals(day)) {
            switch (day == null ? "tomorrow" : day) {
                case "today" -> from = to = today;
                case "all" -> from = to = null;
                default -> {
                    from = today.plusDays(1);
                    to = null;
                }
            }
        }
        if (from != null && to != null && to.isBefore(from)) {
            LocalDate t = from;
            from = to;
            to = t;
        }
        List<Long> agentSel = agentIds == null ? List.of() : agentIds;
        List<Long> regionSel = regionIds == null ? List.of() : regionIds;
        Long expeditor = exp == null || exp.isBlank() ? null : "none".equals(exp) ? OrderSearch.NO_EXPEDITOR : parseId(exp);

        OrderSearch.Page p = search.find(new OrderSearch.Filter(from, to, agentSel, regionSel, expeditor, status, q), page, size);

        AdminPage.head(model, "orders", "Заказы", v.scopeName());
        model.addAttribute("from", from);
        model.addAttribute("to", to);
        model.addAttribute("quick", from == null && to == null ? "all"
                : today.equals(from) && today.equals(to) ? "today"
                : today.plusDays(1).equals(from) && to == null ? "tomorrow" : "");
        model.addAttribute("agents", options(staff.staff(v.companyId(), Role.AGENT), agentSel, v));
        model.addAttribute("regions", routes.regions().stream()
                .filter(r -> v.companyId() == null || v.companyId().equals(r.getCompanyId()))
                .map(r -> new Option(r.getId(), label(r.getName(), r.getCompany(), v), regionSel.contains(r.getId()))).toList());
        model.addAttribute("expeditors", options(staff.staff(v.companyId(), Role.EXPEDITOR),
                expeditor == null ? List.of() : List.of(expeditor), v));
        model.addAttribute("exp", exp == null ? "" : exp);
        model.addAttribute("status", status);
        model.addAttribute("q", q);
        model.addAttribute("statuses", OrderStatus.values());
        model.addAttribute("p", p);
        model.addAttribute("sizes", OrderSearch.SIZES);
        model.addAttribute("link", new QueryLink(request));
        return "admin/orders/list";
    }

    private static Long parseId(String s) {
        try {
            return Long.valueOf(s.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static List<Option> options(List<Employee> people, List<Long> selected, Viewer v) {
        return people.stream().map(e -> new Option(e.getId(), label(e.getName(), e.getCompany(), v), selected.contains(e.getId()))).toList();
    }

    /** В режиме «Все компании» к имени добавляется компания: у разных дилеров бывают тёзки. */
    private static String label(String name, Company company, Viewer v) {
        return v.isAll() && company != null ? name + " · " + company.getName() : name;
    }

    @GetMapping("/admin/orders/{id}")
    public String view(@PathVariable Long id, Model model, HttpSession session) {
        Order o = orders.get(id);
        AdminPage.head(model, "orders", "Заказ " + o.getNumber(), o.getOutlet().getName());
        model.addAttribute("o", o);
        return "admin/orders/view";
    }

    /** Лист сборки на завтра: всё, что принято и ещё не загружено, сложено по товарам. */
    @GetMapping("/admin/orders/pick")
    public String pick(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Order> list = orders.toPick();
        AdminPage.head(model, "orders", "Лист сборки на завтра", v.scopeName() + " · " + fmt.plural(list.size(), "заказ", "заказа", "заказов"));
        model.addAttribute("orders", list);
        model.addAttribute("rows", OrderService.pickList(list));
        return "admin/orders/pick";
    }

    @PostMapping("/admin/orders/{id}/approve")
    public String approve(@PathVariable Long id, HttpSession session) {
        Order o = orders.approve(id, ctx.viewer(session).actor());
        ctx.toast(session, "Заказ " + o.getNumber() + " разрешён");
        return "redirect:/admin/orders/" + id;
    }

    @PostMapping("/admin/orders/{id}/cancel")
    public String cancel(@PathVariable Long id, @RequestParam(defaultValue = "") String reason, HttpSession session) {
        Order o = orders.cancel(id, ctx.viewer(session).actor(), reason.isBlank() ? "без причины" : reason.trim());
        ctx.toast(session, "Заказ " + o.getNumber() + " отменён");
        return "redirect:/admin/orders/" + id;
    }
}
