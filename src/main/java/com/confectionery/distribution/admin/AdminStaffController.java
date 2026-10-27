package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.domain.Vehicle;
import com.confectionery.distribution.service.EmployeeForm;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.IssuedPassword;
import com.confectionery.distribution.service.RouteService;
import com.confectionery.distribution.service.StaffService;
import com.confectionery.distribution.service.VehicleForm;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

@Controller
@RequiredArgsConstructor
public class AdminStaffController {

    private final AdminContext ctx;
    private final StaffService staff;
    private final RouteService routes;

    @GetMapping("/admin/staff")
    public String staff(@RequestParam(defaultValue = "people") String tab, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Employee> people = staff.employees(v.companyId()).stream()
                .sorted(Comparator.comparing(Employee::getCompanyId).thenComparing(e -> e.getRole().ordinal())
                        .thenComparing(Employee::getName)).toList();
        AdminPage.head(model, "staff", "Сотрудники и машины", v.scopeName());
        model.addAttribute("tab", "vehicles".equals(tab) ? "vehicles" : "people");
        model.addAttribute("people", people);
        model.addAttribute("vehicles", staff.vehicles(v.companyId()));
        model.addAttribute("agents", people.stream().filter(e -> e.getRole() == Role.AGENT).count());
        model.addAttribute("expeditors", people.stream().filter(e -> e.getRole() == Role.EXPEDITOR).count());
        model.addAttribute("routes", routes.routes());
        return "admin/staff/list";
    }

    // ------------------------------------------------------------------ сотрудник

    @GetMapping("/admin/staff/new")
    public String create(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        if (v.isAll()) {
            ctx.toast(session, "Выберите компанию в шапке: сотрудник добавляется в одну компанию");
            return "redirect:/admin/staff";
        }
        return employeeForm(model, new EmployeeForm(), null, v.scopeName());
    }

    @GetMapping("/admin/staff/{id}")
    public String edit(@PathVariable Long id, Model model) {
        Employee e = staff.get(id);
        return employeeForm(model, EmployeeForm.of(e), e, e.getCompany().getName());
    }

    /** Новый сотрудник — на список с временным паролем; правка — обратно на его страницу. */
    @PostMapping("/admin/staff/save")
    public String save(@ModelAttribute("f") EmployeeForm f, Model model, HttpSession session, RedirectAttributes ra) {
        Viewer v = ctx.viewer(session);
        try {
            if (f.getId() == null) {
                IssuedPassword issued = staff.create(f, v.companyId());
                ra.addFlashAttribute("issued", issued);
                ctx.toast(session, "Сотрудник «" + issued.name() + "» добавлен");
                return "redirect:/admin/staff";
            }
            Employee e = staff.update(f, v.me().getId());
            ctx.toast(session, e.getName() + " — сохранено");
            return "redirect:/admin/staff/" + e.getId();
        } catch (FormException ex) {
            model.addAttribute("error", ex.getMessage());
            Employee e = f.getId() == null ? null : staff.get(f.getId());
            return employeeForm(model, f, e, e == null ? v.scopeName() : e.getCompany().getName());
        }
    }

    @PostMapping("/admin/staff/{id}/password")
    public String resetPassword(@PathVariable Long id, HttpSession session, RedirectAttributes ra) {
        IssuedPassword issued = staff.resetPassword(id);
        ra.addFlashAttribute("issued", issued);
        ctx.toast(session, "Старый пароль больше не действует");
        return "redirect:/admin/staff/" + id;
    }

    @PostMapping("/admin/staff/{id}/active")
    public String setActive(@PathVariable Long id, @RequestParam boolean on, HttpSession session) {
        Viewer v = ctx.viewer(session);
        try {
            Employee e = staff.setActive(id, on, v.me().getId());
            ctx.toast(session, "«" + e.getName() + "»: " + (on ? "вход снова открыт" : "вход закрыт"));
        } catch (FormException ex) {
            ctx.toast(session, ex.getMessage());
        }
        return "redirect:/admin/staff/" + id;
    }

    private String employeeForm(Model model, EmployeeForm f, Employee e, String sub) {
        AdminPage.head(model, "staff", e == null ? "Новый сотрудник" : e.getName(), sub);
        model.addAttribute("f", f);
        model.addAttribute("e", e);
        model.addAttribute("roles", Arrays.stream(Role.values()).filter(r -> r != Role.SUPER_ADMIN).toList());
        return "admin/staff/form";
    }

    // ------------------------------------------------------------------ машина

    @GetMapping("/admin/staff/vehicles/new")
    public String createVehicle(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        if (v.isAll()) {
            ctx.toast(session, "Выберите компанию в шапке: машина добавляется в одну компанию");
            return "redirect:/admin/staff?tab=vehicles";
        }
        return vehicleForm(model, new VehicleForm(), v.companyId(), v.scopeName());
    }

    @GetMapping("/admin/staff/vehicles/{id}")
    public String editVehicle(@PathVariable Long id, Model model) {
        Vehicle m = staff.vehicle(id);
        return vehicleForm(model, VehicleForm.of(m), m.getCompanyId(), m.getCompany().getName());
    }

    @PostMapping("/admin/staff/vehicles/save")
    public String saveVehicle(@ModelAttribute("f") VehicleForm f, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        try {
            Vehicle m = staff.saveVehicle(f, v.companyId());
            ctx.toast(session, "Машина " + m.getPlate() + " — сохранено");
            return "redirect:/admin/staff?tab=vehicles";
        } catch (FormException ex) {
            model.addAttribute("error", ex.getMessage());
            Vehicle m = f.getId() == null ? null : staff.vehicle(f.getId());
            return vehicleForm(model, f, m == null ? v.companyId() : m.getCompanyId(), m == null ? v.scopeName() : m.getCompany().getName());
        }
    }

    private String vehicleForm(Model model, VehicleForm f, Long companyId, String sub) {
        AdminPage.head(model, "staff", f.getId() == null ? "Новая машина" : "Машина " + f.getPlate(), sub);
        model.addAttribute("f", f);
        model.addAttribute("expeditors", companyId == null ? List.of() : staff.freeExpeditors(companyId, f.getId()));
        return "admin/staff/vehicle";
    }
}
