package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.CompanyForm;
import com.confectionery.distribution.service.CompanyService;
import com.confectionery.distribution.service.DashboardService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.IssuedPassword;
import com.confectionery.distribution.service.SettingsForm;
import com.confectionery.distribution.service.SettingsService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

/** Импорт из Doctor Sales (пока заглушка), компании (владелец) и настройки компании. */
@Controller
@RequiredArgsConstructor
public class AdminSystemController {

    private final AdminContext ctx;
    private final DashboardService dashboard;
    private final SettingsService settings;
    private final CompanyService companies;

    @GetMapping("/admin/import")
    public String importPage(@RequestParam(defaultValue = "1") int step, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "import", "Импорт из Doctor Sales", v.isAll() ? "Выберите компанию, в которую загружать" : "В компанию: " + v.scopeName());
        model.addAttribute("step", Math.max(1, Math.min(3, step)));
        return "admin/import/wizard";
    }

    /** ЗАГЛУШКА: файл не читается — сразу показываем пример предпросмотра. */
    @PostMapping("/admin/import")
    public String upload(@RequestParam(required = false) MultipartFile file, HttpSession session) {
        String name = file == null || file.isEmpty() ? "пример" : file.getOriginalFilename();
        ctx.toast(session, "Файл «" + name + "» принят. Разбор появится, когда пришлёте выгрузку — пока показан пример");
        return "redirect:/admin/import?step=2";
    }

    @GetMapping("/admin/companies")
    public String companies(Model model) {
        if (!model.containsAttribute("f")) model.addAttribute("f", new CompanyForm());
        AdminPage.head(model, "companies", "Компании", "Своя доставка и склады-дилеры · данные каждой отделены");
        model.addAttribute("rows", dashboard.snapshot().companyRows());
        return "admin/companies/list";
    }

    /** Новая компания с директором: его временный пароль показывается один раз, на следующей странице. */
    @PostMapping("/admin/companies")
    public String createCompany(@ModelAttribute("f") CompanyForm f, Model model, HttpSession session, RedirectAttributes ra) {
        try {
            IssuedPassword issued = companies.create(f);
            ctx.toast(session, "Компания «" + f.getName().strip() + "» создана");
            ra.addFlashAttribute("issued", issued);
            return "redirect:/admin/companies";
        } catch (FormException e) {
            model.addAttribute("error", e.getMessage());
            return companies(model);
        }
    }

    @GetMapping("/admin/settings")
    public String settings(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        return settingsPage(model, v, SettingsForm.of(settings.of(v.companyId()), v.company()));
    }

    @PostMapping("/admin/settings")
    public String saveSettings(@ModelAttribute("f") SettingsForm f, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        try {
            settings.save(v.companyId(), f, v.isSuper());
            ctx.toast(session, "Настройки сохранены");
            return "redirect:/admin/settings";
        } catch (FormException e) {
            model.addAttribute("error", e.getMessage());
            // «Клиент в CRM» директор не меняет — показываем сохранённый
            if (!v.isSuper()) f.setCrmClient(v.company() == null ? null : v.company().getCrmClient());
            return settingsPage(model, v, f);
        }
    }

    private String settingsPage(Model model, Viewer v, SettingsForm f) {
        AdminPage.head(model, "settings", "Настройки", v.isAll() ? "Выберите компанию в шапке, чтобы изменить её настройки" : v.scopeName());
        model.addAttribute("f", f);
        return "admin/settings";
    }
}
