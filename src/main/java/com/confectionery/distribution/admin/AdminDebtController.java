package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.CompanySettings;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.service.ApprovalService;
import com.confectionery.distribution.service.DebtService;
import com.confectionery.distribution.service.OutletService;
import com.confectionery.distribution.service.SettingsService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.time.Clock;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/** Долги магазинов (design/admin/AdmDebts): итоги дня сверху, правило запрета, вкладки по статусу. */
@Controller
@RequiredArgsConstructor
public class AdminDebtController {

    private final AdminContext ctx;
    private final OutletService outlets;
    private final DebtService debts;
    private final ApprovalService approvals;
    private final SettingsService settings;
    private final Fmt fmt;
    private final Clock clock;

    /** Строка: магазин, статус («Заказ закрыт», «Скоро запрет», «Просрочка», «Сверх лимита», «В срок») и подпись под ним. */
    public record Row(Outlet o, String state, String badge, String note, boolean block, boolean soon) {
    }

    @GetMapping("/admin/debts")
    public String list(@RequestParam(defaultValue = "all") String f, @RequestParam(defaultValue = "0") int overdue,
                       @RequestParam(required = false) String q, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        String tab = overdue != 0 ? "over" : f;
        LocalDate today = LocalDate.now(clock);
        Map<Long, CompanySettings> st = new HashMap<>();
        Set<Long> unblocked = approvals.unblockedToday();
        List<Row> rows = outlets.list(v.companyId()).stream().filter(o -> o.getDebt() > 0)
                .map(o -> row(o, st.computeIfAbsent(o.getCompanyId(), settings::of), unblocked.contains(o.getId()), today)).toList();
        String needle = q == null ? "" : q.trim().toLowerCase(Locale.ROOT);
        List<Row> list = rows.stream()
                .filter(r -> switch (tab) {
                    case "over" -> r.o().getOverdue() > 0;
                    case "block" -> r.block();
                    case "limit" -> r.o().isOverLimit();
                    case "soon" -> r.soon();
                    default -> true;
                })
                .filter(r -> needle.isEmpty() || r.o().getName().toLowerCase(Locale.ROOT).contains(needle))
                .sorted(Comparator.comparing((Row r) -> !r.block()).thenComparing(r -> !r.soon())
                        .thenComparing(Comparator.comparingLong((Row r) -> r.o().getOverdue()).reversed())
                        .thenComparing(Comparator.comparingLong((Row r) -> r.o().getDebt()).reversed()))
                .toList();
        AdminPage.head(model, "debts", "Долги магазинов", fmt.dot(v.scopeName(), "считается по накладным и оплатам"));
        model.addAttribute("rows", list);
        model.addAttribute("f", tab);
        model.addAttribute("q", q);
        model.addAttribute("count", rows.size());
        model.addAttribute("countOverdue", rows.stream().filter(r -> r.o().getOverdue() > 0).count());
        model.addAttribute("countBlock", rows.stream().filter(Row::block).count());
        model.addAttribute("countLimit", rows.stream().filter(r -> r.o().isOverLimit()).count());
        model.addAttribute("countSoon", rows.stream().filter(Row::soon).count());
        model.addAttribute("total", rows.stream().mapToLong(r -> r.o().getDebt()).sum());
        model.addAttribute("totalOverdue", rows.stream().mapToLong(r -> r.o().getOverdue()).sum());
        model.addAttribute("listDebt", list.stream().mapToLong(r -> r.o().getDebt()).sum());
        model.addAttribute("listOverdue", list.stream().mapToLong(r -> r.o().getOverdue()).sum());
        model.addAttribute("day", debts.today(v.companyId()));
        model.addAttribute("rule", settings.of(v.companyId() != null ? v.companyId() : rows.isEmpty() ? null : rows.get(0).o().getCompanyId()));
        return "admin/debts/list";
    }

    private Row row(Outlet o, CompanySettings s, boolean unblocked, LocalDate today) {
        AdminOutletController.Row r = AdminOutletController.row(o, null, s, today);
        boolean block = s.blocks(o);
        if (block) return new Row(o, "Заказ закрыт", "bad", unblocked ? "сегодня разрешён 1 заказ" : "просрочка " + fmt.plural(o.getOverdueDays(), "день", "дня", "дней"), true, false);
        boolean soon = "Скоро запрет".equals(r.state()) && o.getOverdue() > 0;
        int left = s.getOverdueDays() - o.getOverdueDays() + 1;
        if (soon) return new Row(o, "Скоро запрет", "warn", left > 0 ? "через " + fmt.plural(left, "день", "дня", "дней") : null, false, true);
        if (o.getOverdue() > 0) return new Row(o, "Просрочка", "off", s.isOverdueBlock() && left > 0 ? "до запрета " + fmt.plural(left, "день", "дня", "дней") : null, false, false);
        if (o.isOverLimit()) return new Row(o, "Сверх лимита", "warn", "новые заказы — через разрешение", false, false);
        return new Row(o, "В срок", "done", null, false, false);
    }
}
