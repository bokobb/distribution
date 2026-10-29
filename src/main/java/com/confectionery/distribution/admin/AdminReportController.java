package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.service.CashReport;
import com.confectionery.distribution.service.DashboardService;
import com.confectionery.distribution.service.MapService;
import com.confectionery.distribution.service.SettingsService;
import com.confectionery.distribution.service.WorkdayReport;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.time.Clock;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;

@Controller
@RequiredArgsConstructor
public class AdminReportController {

    private final AdminContext ctx;
    private final DashboardService dashboard;
    private final MapService map;
    private final WorkdayReport workday;
    private final SettingsService settings;
    private final CashReport cashReport;
    private final Fmt fmt;
    private final Clock clock;

    /** Самый длинный период отчёта «Рабочий день», дней. */
    static final int WORKDAY_MAX_DAYS = 31;

    public record ReportCard(String key, String title, String text, boolean ready) {
    }

    private static final List<ReportCard> CARDS = List.of(
            new ReportCard("quality", "Качество: что возвращают магазины", "Негодный товар по товарам — обратная связь для производства.", true),
            new ReportCard("workday", "Рабочий день торговых и экспедиторов", "Начало и конец дня, часы, километры по GPS, когда пропадал GPS, журнал приложения.", true),
            new ReportCard("agents", "Продажи по агентам", "Визиты, заказы, отказы и сумма по каждому агенту за период.", false),
            new ReportCard("outlets", "Продажи по магазинам", "Кто сколько берёт, средний заказ, магазины без заказов.", false),
            new ReportCard("products", "Продажи по товарам", "Штуки и суммы по товарам и категориям, по регионам.", false),
            new ReportCard("cash", "Касса и недостачи", "Получено наличными, сдано в кассу, недостачи и решения по ним — по экспедиторам.", true),
            new ReportCard("debts", "Долги на дату", "Долги магазинов, просрочка, оплаты за период.", false));

    @GetMapping("/admin/reports")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "reports", "Отчёты", v.scopeName());
        model.addAttribute("cards", CARDS);
        return "admin/reports/list";
    }

    /** «Касса и недостачи» за месяц (month = 2026-10), по всем экспедиторам или одному. */
    @GetMapping("/admin/reports/cash")
    public String cash(@RequestParam(required = false) String month, @RequestParam(required = false) Long exp,
                       Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        LocalDate today = LocalDate.now(clock);
        java.time.YearMonth ym;
        try {
            ym = month == null ? java.time.YearMonth.from(today) : java.time.YearMonth.parse(month);
        } catch (java.time.format.DateTimeParseException e) {
            ym = java.time.YearMonth.from(today);
        }
        String title = ym.getMonth().getDisplayName(java.time.format.TextStyle.FULL_STANDALONE, java.util.Locale.forLanguageTag("ru"));
        title = Character.toUpperCase(title.charAt(0)) + title.substring(1) + " " + ym.getYear();
        AdminPage.head(model, "reports", "Касса и недостачи", v.scopeName() + " · " + title);
        CashReport.Report r = cashReport.build(v.companyId(), ym.atDay(1), ym.atEndOfMonth(), exp);
        model.addAttribute("r", r);
        model.addAttribute("all", exp == null ? r : cashReport.build(v.companyId(), ym.atDay(1), ym.atEndOfMonth(), null));
        model.addAttribute("month", ym.toString());
        model.addAttribute("monthTitle", title);
        model.addAttribute("prev", ym.minusMonths(1).toString());
        model.addAttribute("next", ym.isBefore(java.time.YearMonth.from(today)) ? ym.plusMonths(1).toString() : null);
        model.addAttribute("exp", exp);
        model.addAttribute("tolerance", v.companyId() == null ? null : settings.of(v.companyId()).getCashTolerance());
        return "admin/reports/cash";
    }

    @GetMapping("/admin/reports/quality")
    public String quality(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "reports", "Качество: что возвращают магазины", v.scopeName() + " · за всё время");
        model.addAttribute("rows", dashboard.quality(v.companyId()));
        return "admin/reports/quality";
    }

    @GetMapping("/admin/reports/workday")
    public String workday(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                          @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                          @RequestParam(name = "who", required = false) List<Long> who,
                          Model model, HttpSession session, HttpServletRequest request) {
        Viewer v = ctx.viewer(session);
        LocalDate today = LocalDate.now(clock);
        LocalDate b = to != null ? to : from != null ? from : today;
        LocalDate a = from != null ? from : b;
        if (a.isAfter(b)) {
            LocalDate x = a;
            a = b;
            b = x;
        }
        boolean clipped = ChronoUnit.DAYS.between(a, b) >= WORKDAY_MAX_DAYS;
        if (clipped) a = b.minusDays(WORKDAY_MAX_DAYS - 1);
        List<Long> sel = who == null ? List.of() : who;
        List<MapService.Who> people = map.people(v.companyId());
        String period = a.equals(b) ? fmt.longDay(a) : fmt.date(a) + " — " + fmt.date(b);
        AdminPage.head(model, "reports", "Рабочий день", v.scopeName() + " · " + period);
        model.addAttribute("from", a);
        model.addAttribute("to", b);
        model.addAttribute("today", today);
        model.addAttribute("clipped", clipped);
        model.addAttribute("maxDays", WORKDAY_MAX_DAYS);
        model.addAttribute("agents", people.stream().filter(p -> p.role() == Role.AGENT).toList());
        model.addAttribute("expeditors", people.stream().filter(p -> p.role() == Role.EXPEDITOR).toList());
        model.addAttribute("sel", sel);
        model.addAttribute("chosen", people.stream().filter(p -> sel.contains(p.id())).toList());
        model.addAttribute("link", new QueryLink(request));
        model.addAttribute("r", workday.build(v.companyId(), a, b, sel));
        model.addAttribute("gpsInterval", v.companyId() == null ? null : settings.of(v.companyId()).getGpsInterval());
        return "admin/reports/workday";
    }
}
