package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.stub.StubStore;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.Comparator;
import java.util.List;

@Controller
@RequiredArgsConstructor
public class AdminDashboardController {

    private final AdminContext ctx;
    private final StubStore store;
    private final Fmt fmt;

    @GetMapping("/admin/dashboard")
    public String dashboard(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "dashboard", v.scopeName() + " · сегодня", fmt.longDay(store.today()));
        Long cid = v.companyId();
        model.addAttribute("s", store.summary(cid));
        model.addAttribute("alerts", store.alerts(cid));
        model.addAttribute("agents", store.agentsToday(cid));
        List<Trip> trips = store.trips(cid).stream()
                .sorted(Comparator.comparing((Trip t) -> t.getStatus().ordinal())).toList();
        model.addAttribute("trips", trips);
        model.addAttribute("quality", store.quality(cid).stream().limit(5).toList());
        if (v.isAll()) model.addAttribute("companyRows", store.companyRows());
        return "admin/dashboard";
    }
}
