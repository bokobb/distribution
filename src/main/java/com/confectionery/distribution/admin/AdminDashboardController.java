package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.CrmSync;
import com.confectionery.distribution.service.DashboardService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

@Controller
@RequiredArgsConstructor
public class AdminDashboardController {

    private final AdminContext ctx;
    private final DashboardService dashboard;
    private final CrmSync crm;
    private final Fmt fmt;
    private final Clock clock;

    @GetMapping("/admin/dashboard")
    public String dashboard(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        LocalDateTime now = LocalDateTime.now(clock);
        AdminPage.head(model, "dashboard", "Дашборд", fmt.cap(fmt.longDay(now.toLocalDate())) + " · " + fmt.time(now)
                + (v.isAll() ? "" : " · " + v.scopeName()));
        Long cid = v.companyId();
        DashboardService.Snapshot s = dashboard.snapshot();
        model.addAttribute("s", s.summary(cid));
        model.addAttribute("alerts", s.alerts(cid));
        model.addAttribute("agents", s.agents(cid));
        model.addAttribute("trips", s.trips(cid));
        List<DashboardService.StaleOutlet> stale = s.staleOutlets(cid);
        model.addAttribute("stale", stale.stream().limit(6).toList());
        model.addAttribute("staleCount", stale.size());
        if (v.isAll()) {
            model.addAttribute("companyRows", s.companyRows());
            model.addAttribute("crmOn", crm.enabled());
            model.addAttribute("crmOk", crm.enabled() && crm.lastError() == null);
        }
        return "admin/dashboard";
    }
}
