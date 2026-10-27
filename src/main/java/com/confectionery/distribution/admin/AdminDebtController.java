package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.stub.StubStore;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.Comparator;
import java.util.List;

@Controller
@RequiredArgsConstructor
public class AdminDebtController {

    private final AdminContext ctx;
    private final StubStore store;

    @GetMapping("/admin/debts")
    public String list(@RequestParam(defaultValue = "0") int overdue, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Outlet> withDebt = store.outlets(v.companyId()).stream().filter(o -> o.getDebt() > 0).toList();
        List<Outlet> list = withDebt.stream().filter(o -> overdue == 0 || o.getOverdue() > 0)
                .sorted(Comparator.comparingLong(Outlet::getOverdue).reversed().thenComparing(Comparator.comparingLong(Outlet::getDebt).reversed()))
                .toList();
        AdminPage.head(model, "debts", "Долги магазинов", v.scopeName());
        model.addAttribute("outlets", list);
        model.addAttribute("overdueOnly", overdue != 0);
        model.addAttribute("count", withDebt.size());
        model.addAttribute("countOverdue", withDebt.stream().filter(o -> o.getOverdue() > 0).count());
        model.addAttribute("countOver", withDebt.stream().filter(Outlet::isOverLimit).count());
        model.addAttribute("total", withDebt.stream().mapToLong(Outlet::getDebt).sum());
        model.addAttribute("totalOverdue", withDebt.stream().mapToLong(Outlet::getOverdue).sum());
        return "admin/debts/list";
    }
}
