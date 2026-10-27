package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.stub.StubStore;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.*;

import static org.springframework.http.HttpStatus.NOT_FOUND;

@Controller
@RequiredArgsConstructor
public class AdminOrderController {

    private final AdminContext ctx;
    private final StubStore store;

    /** Фильтр по дню доставки: today — развозят сегодня, tomorrow — заказы агентов на завтра. */
    @GetMapping("/admin/orders")
    public String list(@RequestParam(defaultValue = "tomorrow") String day,
                       @RequestParam(required = false) OrderStatus status,
                       @RequestParam(required = false) String q,
                       Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        LocalDate today = store.today();
        List<Order> byDay = store.orders(v.companyId()).stream().filter(o -> switch (day) {
            case "today" -> today.equals(o.getDeliveryDate());
            case "all" -> true;
            default -> o.getDeliveryDate().isAfter(today);
        }).toList();
        Map<OrderStatus, Long> counts = new EnumMap<>(OrderStatus.class);
        for (Order o : byDay) counts.merge(o.getStatus(), 1L, Long::sum);
        String needle = q == null ? "" : q.trim().toLowerCase(Locale.ROOT);
        List<Order> list = byDay.stream()
                .filter(o -> status == null || o.getStatus() == status)
                .filter(o -> needle.isEmpty() || o.getNumber().toLowerCase(Locale.ROOT).contains(needle)
                        || o.getOutlet().getName().toLowerCase(Locale.ROOT).contains(needle)
                        || o.getAgent().getName().toLowerCase(Locale.ROOT).contains(needle))
                .sorted(Comparator.comparing(Order::getCreatedAt).reversed()).toList();
        AdminPage.head(model, "orders", "Заказы", v.scopeName());
        model.addAttribute("day", day);
        model.addAttribute("status", status);
        model.addAttribute("q", q);
        model.addAttribute("statuses", OrderStatus.values());
        model.addAttribute("counts", counts);
        model.addAttribute("total", byDay.size());
        model.addAttribute("orders", list);
        model.addAttribute("sum", list.stream().mapToLong(Order::getTotal).sum());
        return "admin/orders/list";
    }

    @GetMapping("/admin/orders/{id}")
    public String view(@PathVariable Long id, Model model, HttpSession session) {
        Order o = own(id, session);
        AdminPage.head(model, "orders", "Заказ " + o.getNumber(), o.getOutlet().getName());
        model.addAttribute("o", o);
        return "admin/orders/view";
    }

    /** Лист сборки на завтра: всё, что принято и ещё не загружено, сложено по товарам. */
    @GetMapping("/admin/orders/pick")
    public String pick(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Order> list = store.orders(v.companyId()).stream()
                .filter(o -> o.getStatus() == OrderStatus.ACCEPTED || o.getStatus() == OrderStatus.ASSEMBLED)
                .sorted(Comparator.comparing((Order o) -> o.getOutlet().getRoute().getName())).toList();
        AdminPage.head(model, "orders", "Лист сборки на завтра", v.scopeName() + " · " + list.size() + " заказов");
        model.addAttribute("orders", list);
        model.addAttribute("rows", store.pickList(list));
        return "admin/orders/pick";
    }

    @PostMapping("/admin/orders/{id}/approve")
    public String approve(@PathVariable Long id, HttpSession session) {
        Order o = own(id, session);
        store.approveOrder(id, who(session));
        ctx.toast(session, "Заказ " + o.getNumber() + " разрешён");
        return "redirect:/admin/orders/" + id;
    }

    @PostMapping("/admin/orders/{id}/cancel")
    public String cancel(@PathVariable Long id, @RequestParam(defaultValue = "") String reason, HttpSession session) {
        Order o = own(id, session);
        store.cancelOrder(id, who(session), reason.isBlank() ? "без причины" : reason.trim());
        ctx.toast(session, "Заказ " + o.getNumber() + " отменён");
        return "redirect:/admin/orders/" + id;
    }

    private String who(HttpSession session) {
        Viewer v = ctx.viewer(session);
        return v.me().getName() + (v.role() == Role.SUPER_ADMIN ? "" : " (" + v.role().getLabel().toLowerCase() + ")");
    }

    private Order own(Long id, HttpSession session) {
        Order o = store.order(id);
        Viewer v = ctx.viewer(session);
        if (o == null || (!v.isAll() && !o.getCompany().getId().equals(v.companyId())))
            throw new ResponseStatusException(NOT_FOUND);
        return o;
    }
}
