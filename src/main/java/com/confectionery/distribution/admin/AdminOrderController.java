package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Delivery;
import com.confectionery.distribution.domain.DeliveryStatus;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.Payment;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.domain.TripOrder;
import com.confectionery.distribution.repository.PaymentRepository;
import com.confectionery.distribution.service.ApprovalService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.GpsTrack;
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
    private final PaymentRepository payments;
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

        String when = f.from() == null && f.to() == null ? "все даты"
                : f.from() != null && f.from().equals(f.to()) ? "заказы " + fmt.longDay(f.from())
                : f.to() == null ? "заказы с " + fmt.date(f.from()) : f.from() == null ? "заказы по " + fmt.date(f.to())
                : "заказы " + fmt.date(f.from()) + " — " + fmt.date(f.to());
        AdminPage.head(model, "orders", "Заказы", fmt.dot(when, fmt.plural(p.total(), "заказ", "заказа", "заказов") + " на " + fmt.money(p.sum()),
                v.isAll() ? v.scopeName() : null));
        model.addAttribute("notes", approvals.orderNotes(p.rows()));
        model.addAttribute("returns", p.total() == 0 ? 0L : search.returnSum(f));
        model.addAttribute("oneDay", f.from() != null && f.from().equals(f.to()));
        model.addAttribute("from", f.from());
        model.addAttribute("to", f.to());
        model.addAttribute("quick", f.from() == null && f.to() == null ? "all"
                : today.equals(f.from()) && today.equals(f.to()) ? "today"
                : today.minusDays(1).equals(f.from()) && today.minusDays(1).equals(f.to()) ? "yesterday" : "");
        model.addAttribute("agents", options(staff.staff(v.companyId(), Role.AGENT), f.agents(), v));
        model.addAttribute("regions", regions.regions().stream()
                .filter(r -> v.companyId() == null || v.companyId().equals(r.getCompanyId()))
                .map(r -> new Option(r.getId(), label(r.getName(), r.getCompany(), v), f.regions().contains(r.getId()))).toList());
        model.addAttribute("expeditors", options(staff.staff(v.companyId(), Role.EXPEDITOR),
                f.expeditor() == null ? List.of() : List.of(f.expeditor()), v));
        model.addAttribute("exp", exp == null ? "" : exp);
        model.addAttribute("shipTo", staff.staff(v.companyId(), Role.EXPEDITOR).stream().filter(Employee::isActive).toList());
        model.addAttribute("shipDay", today);
        model.addAttribute("shipLast", today.plusDays(TripService.SHIP_DAYS_AHEAD));
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
     * Условия списка из адреса. Дата заказа (когда пришёл): day = today | yesterday | all — быстрый выбор,
     * day = range — «с» и «по» из формы; без условий — сегодня. Экспедитор: пусто — любой, none — ещё не
     * отгружены, id — его рейсы.
     */
    private OrderSearch.Filter filter(String day, LocalDate from, LocalDate to, List<Long> agentIds, List<Long> regionIds,
                                      String exp, OrderStatus status, String q) {
        LocalDate today = LocalDate.now(clock);
        if (!"range".equals(day)) {
            switch (day == null ? "today" : day) {
                case "yesterday" -> from = to = today.minusDays(1);
                case "all" -> from = to = null;
                default -> from = to = today;
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
        Delivery d = o.getDelivery();
        String state = d != null && d.getDeliveredAt() != null
                ? (d.getStatus() == DeliveryStatus.REFUSED ? "отказ " : "доставлен ") + fmt.when(d.getDeliveredAt())
                + (o.getStatus() == OrderStatus.PARTIAL ? ", частично" : "")
                : o.getTrip() != null ? "отгрузка " + fmt.day(o.getTrip().getDate()) : "ждёт отгрузки";
        AdminPage.head(model, "orders", "Заказ " + o.getNumber(), fmt.dot(o.getOutlet().getName(), o.getOutlet().getAddress(), state));
        model.addAttribute("o", o);
        List<Payment> paid = payments.findByOutletOrderByAtDesc(o.getOutlet()).stream()
                .filter(p -> o.equals(p.getOrder()) || p.isOldDebt() && o.getTrip() != null && o.getTrip().equals(p.getTrip())).toList();
        model.addAttribute("paid", paid);
        model.addAttribute("paidOrder", paid.stream().filter(p -> !p.isOldDebt()).mapToLong(Payment::getAmount).sum());
        model.addAttribute("paidOld", paid.stream().filter(Payment::isOldDebt).mapToLong(Payment::getAmount).sum());
        long due = (o.getStatus().delivered() ? o.getDeliveredTotal() : o.getTotal())
                - (o.getReturnLines().isEmpty() ? 0 : o.getReturnTotal());
        model.addAttribute("due", Math.max(0, due));
        model.addAttribute("gps", d == null || d.getLat() == null || o.getOutlet().getLat() == null ? null
                : (int) Math.round(GpsTrack.km(new GpsTrack.At(null, d.getLat(), d.getLng()),
                new GpsTrack.At(null, o.getOutlet().getLat(), o.getOutlet().getLng())) * 1000));
        model.addAttribute("stop", o.getTrip() == null ? null : o.getTrip().getTripOrders().stream()
                .sorted(java.util.Comparator.comparingInt(TripOrder::getPosition)).map(TripOrder::getOrder).toList().indexOf(o) + 1);
        return "admin/orders/view";
    }

    /** Лист сборки: всё новое и собранное, ещё не отгруженное, сложено по товарам. */
    @GetMapping("/admin/orders/pick")
    public String pick(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Order> list = orders.toPick();
        AdminPage.head(model, "orders", "Лист сборки", v.scopeName() + " · " + fmt.plural(list.size(), "заказ", "заказа", "заказов"));
        model.addAttribute("orders", list);
        model.addAttribute("rows", OrderService.pickList(list));
        return "admin/orders/pick";
    }

    /** Итог отгрузки над списком: kind — al--info или al--bad, lines — подробности. */
    public record Notice(String kind, String title, List<String> lines) implements java.io.Serializable {
    }

    /** Отмеченные галочками новые заказы — «Собран»; возврат в тот же список. */
    @PostMapping("/admin/orders/assemble")
    public String assemble(@RequestParam(name = "ids", required = false) List<Long> ids,
                           @RequestParam(required = false) String back,
                           HttpSession session, RedirectAttributes ra) {
        try {
            int n = orders.assemble(ids, ctx.viewer(session).actor());
            int skipped = ids.size() - n;
            ra.addFlashAttribute("notice", n == 0
                    ? new Notice("al--bad", "Ничего не отмечено собранным", List.of("«Собран» ставится только новым заказам"))
                    : new Notice("al--info", "Собрано: " + fmt.plural(n, "заказ", "заказа", "заказов"),
                    skipped == 0 ? List.of() : List.of("Не изменены (уже собраны, отгружены или ждут разрешения): " + skipped)));
        } catch (FormException e) {
            ra.addFlashAttribute("notice", new Notice("al--bad", e.getMessage(), List.of()));
        }
        return "redirect:" + AdminPage.back(back, "/admin/orders");
    }

    /** Отмеченные галочками заказы — экспедитору на выбранный день (см. TripService.ship); возврат в тот же список. */
    @PostMapping("/admin/orders/ship")
    public String ship(@RequestParam(name = "ids", required = false) List<Long> ids,
                       @RequestParam(required = false) Long expeditor,
                       @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
                       @RequestParam(required = false) String back,
                       HttpSession session, RedirectAttributes ra) {
        String to = AdminPage.back(back, "/admin/orders");
        try {
            TripService.Shipment s = trips.ship(ids, expeditor, date, ctx.viewer(session).actor());
            List<String> lines = new java.util.ArrayList<>();
            s.skipped().forEach((why, numbers) -> lines.add("Не отгружены — " + why + ": № " + String.join(", № ", numbers)));
            if (s.shipped() == 0) {
                ra.addFlashAttribute("notice", new Notice("al--bad", "Ничего не отгружено", lines));
            } else {
                var t = s.trips().get(0);
                ra.addFlashAttribute("notice", new Notice("al--info", "Отгружено " + fmt.plural(s.shipped(), "заказ", "заказа", "заказов")
                        + " экспедитору " + s.expeditor().getName() + " на " + fmt.longDay(t.getDate()) + ", рейс " + t.getNumber()
                        + " — в телефоне экспедитора с этого дня", lines));
            }
        } catch (FormException e) {
            ra.addFlashAttribute("notice", new Notice("al--bad", e.getMessage(), List.of()));
        }
        return "redirect:" + to;
    }

    /**
     * Накладные по отмеченным заказам, страница для печати: kind = shop — на каждый магазин своя
     * накладная (отдельный лист), total — общая (см. OrderService.waybill).
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
        invoiceModel(list, "total".equals(kind), model, fmt);
        return "admin/orders/invoices";
    }

    /** Данные страницы накладных — и для рейса (AdminTripController). */
    static void invoiceModel(List<Order> list, boolean total, Model model, Fmt fmt) {
        java.util.Set<LocalDate> days = new java.util.TreeSet<>();
        list.forEach(o -> days.add(o.getTrip() != null ? o.getTrip().getDate() : o.getDeliveryDate()));
        java.util.List<com.confectionery.distribution.domain.Trip> tripList = list.stream().map(Order::getTrip)
                .filter(java.util.Objects::nonNull).distinct().toList();
        model.addAttribute("total", total);
        model.addAttribute("orders", list);
        model.addAttribute("sum", list.stream().mapToLong(Order::getTotal).sum());
        model.addAttribute("bill", total ? OrderService.waybill(list) : null);
        model.addAttribute("days", days.stream().map(fmt::date).collect(java.util.stream.Collectors.joining(", ")));
        model.addAttribute("expeditors", tripList.stream().map(t -> t.getExpeditor().getName()).distinct()
                .collect(java.util.stream.Collectors.joining(", ")));
        model.addAttribute("cars", tripList.stream().map(t -> t.getVehicle().getPlate()).distinct()
                .collect(java.util.stream.Collectors.joining(", ")));
        model.addAttribute("tripsText", tripList.stream().map(com.confectionery.distribution.domain.Trip::getNumber)
                .collect(java.util.stream.Collectors.joining(", ")));
        model.addAttribute("agentsText", list.stream().map(Order::getAgent).filter(java.util.Objects::nonNull).map(Employee::getName)
                .distinct().sorted().collect(java.util.stream.Collectors.joining(", ")));
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
