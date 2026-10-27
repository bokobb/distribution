package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.DashboardService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.time.Clock;
import java.time.LocalDate;

@Controller
@RequiredArgsConstructor
public class AdminDashboardController {

    private final AdminContext ctx;
    private final DashboardService dashboard;
    private final Fmt fmt;
    private final Clock clock;

    @GetMapping("/admin/dashboard")
    public String dashboard(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "dashboard", v.scopeName() + " · сегодня", fmt.longDay(LocalDate.now(clock)));
        Long cid = v.companyId();
        DashboardService.Snapshot s = dashboard.snapshot();
        model.addAttribute("s", s.summary(cid));
        model.addAttribute("alerts", s.alerts(cid));
        model.addAttribute("agents", s.agents(cid));
        model.addAttribute("trips", s.trips(cid));
        model.addAttribute("quality", s.quality(cid).stream().limit(5).toList());
        if (v.isAll()) model.addAttribute("companyRows", s.companyRows());
        return "admin/dashboard";
    }
}
