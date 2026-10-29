package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.service.ApprovalService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.MapService;
import com.confectionery.distribution.service.OrderSearch;
import com.confectionery.distribution.service.OrderService;
import com.confectionery.distribution.service.RegionService;
import com.confectionery.distribution.service.StaffService;
import com.confectionery.distribution.service.TripService;
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
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;

@Controller
@RequiredArgsConstructor
public class AdminOrderController {

    private final AdminContext ctx;
    private final ApprovalService approvals;
    private final OrderService orders;
    private final OrderSearch search;
    private final StaffService staff;
    private final TripService trips;
    private final MapService map;
    private final RegionService regions;
    private final Fmt fmt;
    private final Clock clock;

    /** Пункт выпадающего фильтра: торговый, филиал, экспедитор. */
    public record Option(Long id, String name, boolean on) {
    }

    /** Заказы с фильтрами (см. filter): торговые и филиалы — несколько сразу, внизу — страницы. */
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
        OrderSearch.Filter f = filter(day, from, to, agentIds, regionIds, exp, status, q);
        OrderSearch.Page p = search.find(f, page, size);

        AdminPage.head(model, "orders", "Заказы", v.scopeName());
        model.addAttribute("from", f.from());
        model.addAttribute("to", f.to());
        model.addAttribute("quick", f.from() == null && f.to() == null ? "all"
                : today.equals(f.from()) && today.equals(f.to()) ? "today"
                : today.plusDays(1).equals(f.from()) && f.to() == null ? "tomorrow" : "");
        model.addAttribute("agents", options(staff.staff(v.companyId(), Role.AGENT), f.agents(), v));
        model.addAttribute("regions", regions.regions().stream()
                .filter(r -> v.companyId() == null || v.companyId().equals(r.getCompanyId()))
                .map(r -> new Option(r.getId(), label(r.getName(), r.getCompany(), v), f.regions().contains(r.getId()))).toList());
        model.addAttribute("expeditors", options(staff.staff(v.companyId(), Role.EXPEDITOR),
                f.expeditor() == null ? List.of() : List.of(f.expeditor()), v));
        model.addAttribute("exp", exp == null ? "" : exp);
        model.addAttribute("shipTo", staff.staff(v.companyId(), Role.EXPEDITOR).stream().filter(Employee::isActive).toList());
        model.addAttribute("status", status);
        model.addAttribute("q", q);
        model.addAttribute("statuses", OrderStatus.values());
        model.addAttribute("p", p);
        model.addAttribute("sizes", OrderSearch.SIZES);
        model.addAttribute("link", new QueryLink(request));
        return "admin/orders/list";
    }

    /** Сколько заказов самое большее показывает карта списка. */
    private static final int MAP_LIMIT = 2000;

    /** Магазины найденных заказов для карты над списком — те же условия, что у списка. */
    @GetMapping("/admin/orders/map-data")
    @ResponseBody
    public MapService.OrdersMap mapData(@RequestParam(required = false) String day,
                                        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                                        @RequestParam(name = "agent", required = false) List<Long> agentIds,
                                        @RequestParam(name = "region", required = false) List<Long> regionIds,
                                        @RequestParam(required = false) String exp,
                                        @RequestParam(required = false) OrderStatus status,
                                        @RequestParam(required = false) String q,
                                        HttpSession session) {
        List<Order> list = search.all(filter(day, from, to, agentIds, regionIds, exp, status, q), MAP_LIMIT + 1);
        boolean cut = list.size() > MAP_LIMIT;
        return map.orders(ctx.viewer(session).companyId(), cut ? list.subList(0, MAP_LIMIT) : list, cut);
    }

    /**
     * Условия списка из адреса. Дата доставки: day = today | tomorrow (завтра и позже) | all — быстрый
     * выбор, day = range — «с» и «по» из формы; без условий — завтра и позже. Экспедитор: пусто — любой,
     * none — ещё не отгружены, id — его рейсы.
     */
    private OrderSearch.Filter filter(String day, LocalDate from, LocalDate to, List<Long> agentIds, List<Long> regionIds,
                                      String exp, OrderStatus status, String q) {
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
        Long expeditor = exp == null || exp.isBlank() ? null : "none".equals(exp) ? OrderSearch.NO_EXPEDITOR : parseId(exp);
        return new OrderSearch.Filter(from, to, agentIds, regionIds, expeditor, status, q);
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

    /** Итог отгрузки над списком: kind — al--info или al--bad, lines — подробности. */
    public record Notice(String kind, String title, List<String> lines) implements java.io.Serializable {
    }

    /** Отмеченные галочками заказы — экспедитору (см. TripService.ship); возврат в тот же список. */
    @PostMapping("/admin/orders/ship")
    public String ship(@RequestParam(name = "ids", required = false) List<Long> ids,
                       @RequestParam(required = false) Long expeditor,
                       @RequestParam(required = false) String back,
                       HttpSession session, RedirectAttributes ra) {
        String to = AdminPage.back(back, "/admin/orders");
        try {
            TripService.Shipment s = trips.ship(ids, expeditor, ctx.viewer(session).actor());
            List<String> lines = new java.util.ArrayList<>();
            s.skipped().forEach((why, numbers) -> lines.add("Не отгружены — " + why + ": № " + String.join(", № ", numbers)));
            if (s.shipped() == 0) {
                ra.addFlashAttribute("notice", new Notice("al--bad", "Ничего не отгружено", lines));
            } else {
                String tripsText = s.trips().stream().map(t -> t.getNumber() + " (" + fmt.day(t.getDate()) + ")")
                        .collect(java.util.stream.Collectors.joining(", "));
                ra.addFlashAttribute("notice", new Notice("al--info", "Отгружено " + fmt.plural(s.shipped(), "заказ", "заказа", "заказов")
                        + " экспедитору " + s.expeditor().getName() + ": " + (s.trips().size() == 1 ? "рейс " : "рейсы ") + tripsText, lines));
            }
        } catch (FormException e) {
            ra.addFlashAttribute("notice", new Notice("al--bad", e.getMessage(), List.of()));
        }
        return "redirect:" + to;
    }

    /**
     * Накладные по отмеченным заказам, страница для печати: kind = shop — на каждый магазин своя
     * накладная (отдельный лист), total — общая: товар по всем заказам и список магазинов.
     */
    @PostMapping("/admin/orders/invoices")
    public String invoices(@RequestParam(name = "ids", required = false) List<Long> ids,
                           @RequestParam(defaultValue = "shop") String kind, Model model) {
        return invoicePage(orders.forInvoices(ids), kind, model);
    }

    @GetMapping("/admin/orders/{id}/invoice")
    public String invoice(@PathVariable Long id, Model model) {
        return invoicePage(List.of(orders.get(id)), "shop", model);
    }

    private String invoicePage(List<Order> list, String kind, Model model) {
        boolean total = "total".equals(kind);
        java.util.Map<com.confectionery.distribution.domain.PaymentMethod, Long> byPayment =
                new java.util.EnumMap<>(com.confectionery.distribution.domain.PaymentMethod.class);
        for (Order o : list) byPayment.merge(o.getPayment(), o.getTotal(), Long::sum);
        java.util.Set<LocalDate> days = new java.util.TreeSet<>();
        list.forEach(o -> days.add(o.getDeliveryDate()));
        model.addAttribute("total", total);
        model.addAttribute("orders", list);
        model.addAttribute("rows", OrderService.sumList(list));
        model.addAttribute("byPayment", byPayment);
        model.addAttribute("sum", list.stream().mapToLong(Order::getTotal).sum());
        model.addAttribute("qty", list.stream().mapToInt(Order::getQty).sum());
        model.addAttribute("shops", list.stream().map(Order::getOutlet).distinct().count());
        model.addAttribute("days", days.stream().map(fmt::date).collect(java.util.stream.Collectors.joining(", ")));
        model.addAttribute("tripsText", list.stream().map(Order::getTrip).filter(java.util.Objects::nonNull).distinct()
                .map(t -> t.getNumber() + " — " + t.getExpeditor().getName() + ", " + t.getVehicle().getPlate())
                .collect(java.util.stream.Collectors.joining("; ")));
        return "admin/orders/invoices";
    }

    @PostMapping("/admin/orders/{id}/approve")
    public String approve(@PathVariable Long id, HttpSession session) {
        Viewer v = ctx.viewer(session);
        try {
            ctx.toast(session, approvals.decide("o" + id, "OK", v.actor(), v.role()));
        } catch (FormException e) {
            ctx.toast(session, e.getMessage());
        }
        return "redirect:/admin/orders/" + id;
    }

    @PostMapping("/admin/orders/{id}/cancel")
    public String cancel(@PathVariable Long id, @RequestParam(defaultValue = "") String reason, HttpSession session) {
        Order o = orders.cancel(id, ctx.viewer(session).actor(), reason.isBlank() ? "без причины" : reason.trim());
        ctx.toast(session, "Заказ " + o.getNumber() + " отменён");
        return "redirect:/admin/orders/" + id;
    }
}
