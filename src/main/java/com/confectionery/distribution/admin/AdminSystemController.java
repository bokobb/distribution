package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.DashboardService;
import com.confectionery.distribution.service.SettingsService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;

/** Импорт из Doctor Sales, компании (владелец) и настройки компании. Пока всё — заглушки. */
@Controller
@RequiredArgsConstructor
public class AdminSystemController {

    private final AdminContext ctx;
    private final DashboardService dashboard;
    private final SettingsService settings;

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
        AdminPage.head(model, "companies", "Компании", "Своя доставка и склады-дилеры · данные каждой отделены");
        model.addAttribute("rows", dashboard.snapshot().companyRows());
        return "admin/companies/list";
    }

    @PostMapping("/admin/companies")
    public String createCompany(@RequestParam String name, HttpSession session) {
        ctx.toast(session, "Компания «" + name + "»: создание заработает на этапе 1");
        return "redirect:/admin/companies";
    }

    @GetMapping("/admin/settings")
    public String settings(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "settings", "Настройки", v.isAll() ? "Выберите компанию в шапке, чтобы изменить её настройки" : v.scopeName());
        model.addAttribute("st", settings.of(v.companyId()));
        return "admin/settings";
    }

    @PostMapping("/admin/settings")
    public String saveSettings(HttpSession session) {
        ctx.toast(session, "Настройки: сохранение заработает на этапе 1");
        return "redirect:/admin/settings";
    }
}
