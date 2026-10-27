package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.DashboardService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.List;

@Controller
@RequiredArgsConstructor
public class AdminReportController {

    private final AdminContext ctx;
    private final DashboardService dashboard;

    public record ReportCard(String key, String title, String text, boolean ready) {
    }

    private static final List<ReportCard> CARDS = List.of(
            new ReportCard("quality", "Качество: что возвращают магазины", "Негодный товар по товарам и причинам — обратная связь для производства.", true),
            new ReportCard("agents", "Продажи по агентам", "Визиты, заказы, отказы и сумма по каждому агенту за период.", false),
            new ReportCard("outlets", "Продажи по магазинам", "Кто сколько берёт, средний заказ, магазины без заказов.", false),
            new ReportCard("products", "Продажи по товарам", "Штуки и суммы по товарам и категориям, по регионам.", false),
            new ReportCard("cash", "Касса и недостачи", "Наличные по рейсам, сдано, разница по экспедиторам.", false),
            new ReportCard("debts", "Долги на дату", "Долги магазинов, просрочка, оплаты за период.", false));

    @GetMapping("/admin/reports")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "reports", "Отчёты", v.scopeName());
        model.addAttribute("cards", CARDS);
        return "admin/reports/list";
    }

    @GetMapping("/admin/reports/quality")
    public String quality(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "reports", "Качество: что возвращают магазины", v.scopeName() + " · за всё время");
        model.addAttribute("rows", dashboard.quality(v.companyId()));
        return "admin/reports/quality";
    }
}
