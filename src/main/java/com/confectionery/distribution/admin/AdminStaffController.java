package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
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
public class AdminStaffController {

    private final AdminContext ctx;
    private final StubStore store;

    @GetMapping("/admin/staff")
    public String staff(@RequestParam(defaultValue = "people") String tab, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Employee> people = store.employees(v.companyId()).stream()
                .sorted(Comparator.comparing((Employee e) -> e.getCompany().getId()).thenComparing(e -> e.getRole().ordinal())
                        .thenComparing(Employee::getName)).toList();
        AdminPage.head(model, "staff", "Сотрудники и машины", v.scopeName());
        model.addAttribute("tab", "vehicles".equals(tab) ? "vehicles" : "people");
        model.addAttribute("people", people);
        model.addAttribute("vehicles", store.vehicles(v.companyId()));
        model.addAttribute("agents", people.stream().filter(e -> e.getRole() == Role.AGENT).count());
        model.addAttribute("expeditors", people.stream().filter(e -> e.getRole() == Role.EXPEDITOR).count());
        model.addAttribute("routes", store.routes(v.companyId()));
        return "admin/staff/list";
    }
}
