package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.CompanySettings;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.OutletStatus;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.repository.PriceTypeRepository;
import com.confectionery.distribution.service.ApprovalService;
import com.confectionery.distribution.service.AssignService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.NotFoundException;
import com.confectionery.distribution.service.OutletForm;
import com.confectionery.distribution.service.OutletService;
import com.confectionery.distribution.service.RegionService;
import com.confectionery.distribution.service.SettingsService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Controller
@RequiredArgsConstructor
public class AdminOutletController {

    private final AdminContext ctx;
    private final ApprovalService approvals;
    private final OutletService outlets;
    private final RegionService regions;
    private final com.confectionery.distribution.service.StaffService staff;
    private final SettingsService settings;
    private final PriceTypeRepository priceTypes;
    private final Fmt fmt;
    private final Clock clock;

    /** Строка списка: статус по долгу и визитам — «Заказ закрыт», «Скоро запрет», «Без визита 9 дн.»; rank — сначала требующие внимания. */
    public record Row(Outlet o, LocalDateTime lastVisit, String state, String badge, String f, int rank) {
    }

    /** Магазины: новые на проверке — карточками сверху; вкладки по статусу, район и торговый; сначала требующие внимания. */
    @GetMapping("/admin/outlets")
    public String list(@RequestParam(defaultValue = "all") String f,
                       @RequestParam(required = false) Long region,
                       @RequestParam(required = false) Long agent,
                       @RequestParam(required = false) String q,
                       Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Outlet> all = outlets.list(v.companyId());
        Map<Long, LocalDateTime> visits = outlets.lastVisits(v.companyId());
        Map<Long, CompanySettings> st = new HashMap<>();
        LocalDate today = LocalDate.now(clock);
        List<Row> rows = all.stream().map(o -> row(o, visits.get(o.getId()), st.computeIfAbsent(o.getCompanyId(), settings::of), today)).toList();
        Map<String, Long> counts = new HashMap<>();
        for (Row r : rows) {
            if (r.f().equals("closed")) {
                counts.merge("closed", 1L, Long::sum);
                continue;
            }
            counts.merge("all", 1L, Long::sum);
            if (r.o().getStatus() == OutletStatus.PENDING) counts.merge("new", 1L, Long::sum);
            if (r.f().equals("block")) counts.merge("block", 1L, Long::sum);
            if (r.o().getOverdue() > 0) counts.merge("over", 1L, Long::sum);
            if (stale(r.lastVisit(), today) && r.o().getStatus() != OutletStatus.PENDING) counts.merge("stale", 1L, Long::sum);
        }
        String needle = q == null ? "" : q.trim().toLowerCase(Locale.ROOT);
        List<Row> list = rows.stream()
                .filter(r -> switch (f) {
                    case "new" -> r.o().getStatus() == OutletStatus.PENDING;
                    case "block" -> r.f().equals("block");
                    case "over" -> r.o().getOverdue() > 0 && !r.f().equals("closed");
                    case "stale" -> stale(r.lastVisit(), today) && r.o().getStatus() == OutletStatus.ACTIVE;
                    case "closed" -> r.f().equals("closed");
                    default -> !r.f().equals("closed");
                })
                .filter(r -> region == null || (r.o().getRegion() != null && region.equals(r.o().getRegion().getId())))
                .filter(r -> agent == null || (r.o().getAgent() != null && agent.equals(r.o().getAgent().getId())))
                .filter(r -> needle.isEmpty() || Stream.of(r.o().getName(), r.o().getOwner(), r.o().getPhone(), r.o().getAddress()).filter(Objects::nonNull)
                        .collect(Collectors.joining(" ")).toLowerCase(Locale.ROOT).contains(needle))
                .sorted(Comparator.comparingInt(Row::rank).thenComparing(r -> r.o().getName())).toList();
        AdminPage.head(model, "outlets", "Магазины", fmt.dot(fmt.plural(counts.getOrDefault("all", 0L), "магазин", "магазина", "магазинов"), v.scopeName()));
        model.addAttribute("rows", list);
        model.addAttribute("counts", counts);
        model.addAttribute("f", f);
        model.addAttribute("pending", approvals.page(v.companyId(), v.role()).items().stream()
                .filter(i -> i.kind() == com.confectionery.distribution.domain.ApprovalKind.OUTLET).toList());
        model.addAttribute("regions", regions.regions().stream().filter(r -> v.companyId() == null || v.companyId().equals(r.getCompanyId())).toList());
        model.addAttribute("region", region);
        model.addAttribute("agents", staff.staff(v.companyId(), com.confectionery.distribution.domain.Role.AGENT));
        model.addAttribute("agent", agent);
        model.addAttribute("q", q);
        return "admin/outlets/list";
    }

    static boolean stale(LocalDateTime lastVisit, LocalDate today) {
        return lastVisit == null || ChronoUnit.DAYS.between(lastVisit.toLocalDate(), today) >= AssignService.STALE_DAYS;
    }

    /** Статус строки: закрыт → на проверке → заказ закрыт → скоро запрет → без визита → работает. */
    static Row row(Outlet o, LocalDateTime lastVisit, CompanySettings s, LocalDate today) {
        if (o.getStatus() == OutletStatus.CLOSED) return new Row(o, lastVisit, "Закрыт", "off", "closed", 9);
        if (o.getStatus() == OutletStatus.PENDING) return new Row(o, lastVisit, "На проверке", "new", "new", 2);
        if (s.blocks(o)) return new Row(o, lastVisit, "Заказ закрыт", "bad", "block", 0);
        boolean soon = s.isOverdueBlock() && o.getOverdue() > 0
                && (o.getOverdueDays() >= s.getOverdueDays() - 3 || o.getOverdue() * 10 >= s.getOverdueAmount() * 8)
                || o.getCreditLimit() > 0 && o.getDebt() * 10 >= o.getCreditLimit() * 9;
        if (soon) return new Row(o, lastVisit, "Скоро запрет", "warn", "over", 1);
        if (stale(lastVisit, today)) {
            String text = lastVisit == null ? "Визитов не было" : "Без визита " + ChronoUnit.DAYS.between(lastVisit.toLocalDate(), today) + " дн.";
            return new Row(o, lastVisit, text, "warn", "stale", 3);
        }
        return new Row(o, lastVisit, "Работает", "done", "all", o.getOverdue() > 0 ? 4 : 5);
    }

    @GetMapping("/admin/outlets/{id}")
    public String view(@PathVariable Long id, Model model, HttpSession session) {
        Outlet o = outlets.get(id);
        AdminPage.head(model, "outlets", "Магазин " + o.getName(), fmt.dot(o.getAddress(), o.getAgent() == null ? null : o.getAgent().getName(),
                o.getRegion() == null ? null : o.getRegion().getName()));
        model.addAttribute("o", o);
        List<com.confectionery.distribution.domain.Order> orders = outlets.ordersOf(o);
        model.addAttribute("orders", orders.stream().limit(10).toList());
        LocalDate today = LocalDate.now(clock);
        List<com.confectionery.distribution.domain.Order> recent = orders.stream()
                .filter(x -> x.getStatus() != com.confectionery.distribution.domain.OrderStatus.CANCELLED
                        && !x.getCreatedAt().toLocalDate().isBefore(today.minusMonths(3))).toList();
        model.addAttribute("orders3m", recent.size());
        model.addAttribute("avgOrder", recent.isEmpty() ? 0 : recent.stream().mapToLong(com.confectionery.distribution.domain.Order::getTotal).sum() / recent.size());
        Map<Long, com.confectionery.distribution.domain.Order> byVisit = new HashMap<>();
        orders.forEach(x -> {
            if (x.getVisit() != null) byVisit.putIfAbsent(x.getVisit().getId(), x);
        });
        model.addAttribute("visits", outlets.visitsOf(o));
        model.addAttribute("byVisit", byVisit);
        model.addAttribute("payments", outlets.paymentsOf(o));
        model.addAttribute("returns", outlets.returnsOf(o));
        CompanySettings st = settings.of(o.getCompanyId());
        model.addAttribute("st", st);
        model.addAttribute("dayPct", Math.min(100, o.getOverdueDays() * 100 / Math.max(1, st.getOverdueDays())));
        model.addAttribute("sumPct", Math.min(100, o.getOverdue() * 100 / Math.max(1, st.getOverdueAmount())));
        Row r = row(o, null, st, today);
        model.addAttribute("block", st.blocks(o));
        model.addAttribute("soon", !st.blocks(o) && "Скоро запрет".equals(r.state()) ? (o.getOverdue() > 0 && st.getOverdueDays() >= o.getOverdueDays()
                ? "Скоро запрет: через " + fmt.plural(st.getOverdueDays() - o.getOverdueDays() + 1, "день", "дня", "дней") : "Скоро запрет") : null);
        return "admin/outlets/view";
    }

    /** Фото фасада, которое снял агент. */
    @GetMapping("/admin/outlets/{id}/photo")
    public ResponseEntity<Resource> photo(@PathVariable Long id) {
        Path file = outlets.facadeFile(outlets.get(id)).orElseThrow(NotFoundException::new);
        return ResponseEntity.ok().contentType(MediaType.IMAGE_JPEG)
                .cacheControl(CacheControl.maxAge(Duration.ofDays(1)).cachePrivate()).body(new FileSystemResource(file));
    }

    @GetMapping("/admin/outlets/new")
    public String create(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        if (v.isAll()) {
            ctx.toast(session, "Выберите компанию в шапке: магазин добавляется в одну компанию");
            return "redirect:/admin/outlets";
        }
        OutletForm f = new OutletForm();
        f.setCreditLimit(String.valueOf(settings.of(v.companyId()).getDefaultCreditLimit()));
        f.setPaymentDays("7");
        priceTypes.findByCompanyIdAndCode(v.companyId(), PriceKind.WHOLESALE).ifPresent(t -> f.setPriceTypeId(t.getId()));
        return form(model, f, v.companyId(), v.scopeName());
    }

    @GetMapping("/admin/outlets/{id}/edit")
    public String edit(@PathVariable Long id, Model model) {
        Outlet o = outlets.get(id);
        return form(model, OutletForm.of(o), o.getCompanyId(), o.getName());
    }

    @PostMapping("/admin/outlets/save")
    public String save(@ModelAttribute("f") OutletForm f, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        try {
            Outlet o = outlets.save(f, v.companyId(), v.who());
            ctx.toast(session, "«" + o.getName() + "» — сохранено");
            return "redirect:/admin/outlets/" + o.getId();
        } catch (FormException e) {
            model.addAttribute("error", e.getMessage());
            Outlet o = f.getId() == null ? null : outlets.get(f.getId());
            return form(model, f, o == null ? v.companyId() : o.getCompanyId(), o == null ? v.scopeName() : o.getName());
        }
    }

    /** Форма магазина: торговые, районы и типы цен — только компании этого магазина. */
    private String form(Model model, OutletForm f, Long companyId, String sub) {
        AdminPage.head(model, "outlets", f.getId() == null ? "Новый магазин" : "Изменить магазин", sub);
        model.addAttribute("f", f);
        model.addAttribute("agents", staff.employees(companyId).stream()
                .filter(e -> e.getRole() == com.confectionery.distribution.domain.Role.AGENT && e.isActive()).toList());
        model.addAttribute("regions", regions.regions().stream().filter(r -> r.getCompanyId().equals(companyId)).toList());
        model.addAttribute("priceTypes", priceTypes.findByCompanyIdOrderByIdAsc(companyId));
        return "admin/outlets/form";
    }

    @PostMapping("/admin/outlets/{id}/approve")
    public String approve(@PathVariable Long id, HttpSession session) {
        Viewer v = ctx.viewer(session);
        try {
            ctx.toast(session, approvals.decide("s" + id, "OK", v.actor(), v.role()));
        } catch (FormException e) {
            ctx.toast(session, e.getMessage());
        }
        return "redirect:/admin/outlets/" + id;
    }
}
