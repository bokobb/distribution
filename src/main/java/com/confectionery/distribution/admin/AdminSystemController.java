package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.security.LoginJournal;
import com.confectionery.distribution.service.CompanyForm;
import com.confectionery.distribution.service.CompanyService;
import com.confectionery.distribution.service.CrmSync;
import com.confectionery.distribution.service.DashboardService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.IssuedPassword;
import com.confectionery.distribution.service.SettingsForm;
import com.confectionery.distribution.service.SettingsService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

/** Импорт из Doctor Sales (пока заглушка), компании (владелец) со связью с CRM и журналом входов, настройки компании. */
@Controller
@RequiredArgsConstructor
public class AdminSystemController {

    private final AdminContext ctx;
    private final DashboardService dashboard;
    private final SettingsService settings;
    private final CompanyService companies;
    private final CrmSync crm;
    private final LoginJournal journal;
    @Value("${distribution.crm.key:}")
    private String crmKey;

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
        AdminPage.head(model, "companies", "Компании", "Своя доставка и склады-дилеры · у каждой своя админка и приложение для команды");
        List<DashboardService.CompanyRow> rows = dashboard.snapshot().companyRows();
        Set<Long> taken = rows.stream().map(r -> r.company().getCrmClientId()).filter(Objects::nonNull).collect(Collectors.toSet());
        List<CrmSync.CrmClient> clients = crm.clients();
        model.addAttribute("rows", rows);
        model.addAttribute("crmOn", crm.enabled());
        model.addAttribute("crmOk", crm.enabled() && crm.lastError() == null);
        model.addAttribute("crmError", crm.lastError());
        model.addAttribute("crmKey", crmKey == null || crmKey.isBlank() ? null : "••••" + crmKey.strip().substring(Math.max(0, crmKey.strip().length() - 4)));
        model.addAttribute("crmClients", clients);
        model.addAttribute("crmFree", clients.stream().filter(c -> !taken.contains(c.id())).toList());
        model.addAttribute("journal", journal.recent(12));
        return "admin/companies/list";
    }

    /** Новая компания с директором: его временный пароль показывается один раз, на следующей странице. */
    @PostMapping("/admin/companies")
    public String createCompany(@ModelAttribute("f") CompanyForm f, Model model, HttpSession session, RedirectAttributes ra) {
        try {
            if (f.getCrmClientId() != null) f.setCrmClient(crmName(f.getCrmClientId()));
            IssuedPassword issued = companies.create(f);
            ctx.toast(session, "Компания «" + f.getName().strip() + "» создана");
            ra.addFlashAttribute("issued", issued);
            return "redirect:/admin/companies";
        } catch (FormException e) {
            model.addAttribute("error", e.getMessage());
            return companies(model);
        }
    }

    /** Директор компании — клиент CRM: выбор из списка CRM; пусто — связь снята. */
    @PostMapping("/admin/companies/{id}/crm")
    public String linkCrm(@PathVariable Long id, @RequestParam(required = false) Long clientId, HttpSession session) {
        try {
            Company c = companies.linkCrm(id, clientId, clientId == null ? null : crmName(clientId));
            ctx.toast(session, clientId == null ? "«" + c.getName() + "»: связь с CRM снята"
                    : "«" + c.getName() + "»: директор — клиент CRM «" + c.getCrmClient() + "». Отгрузки придут при следующем обмене");
        } catch (FormException e) {
            ctx.toast(session, e.getMessage());
        }
        return "redirect:/admin/companies";
    }

    /** Обмен с CRM сейчас, не дожидаясь минуты (владелец). */
    @PostMapping("/admin/settings/crm-sync")
    public String crmSync(HttpSession session) {
        Viewer v = ctx.viewer(session);
        if (!v.isSuper()) {
            ctx.toast(session, "Обмен с CRM запускает владелец");
        } else if (!crm.enabled()) {
            ctx.toast(session, "Связь с CRM не настроена: на сервере нужны CRM_URL и CRM_KEY");
        } else {
            int n = crm.sync();
            ctx.toast(session, crm.lastError() != null ? "CRM не ответила: " + crm.lastError()
                    : n == 0 ? "Обмен с CRM прошёл · новых отгрузок нет" : "Обмен с CRM прошёл · новых приходов: " + n);
        }
        return "redirect:/admin/settings";
    }

    private String crmName(Long clientId) {
        return crm.clients().stream().filter(c -> c.id().equals(clientId)).map(CrmSync.CrmClient::name).findFirst()
                .orElseThrow(() -> new FormException("Клиента нет в CRM или CRM не ответила — обновите страницу"));
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
            settings.save(v.companyId(), f);
            ctx.toast(session, "Настройки сохранены");
            return "redirect:/admin/settings";
        } catch (FormException e) {
            model.addAttribute("error", e.getMessage());
            // «Клиент в CRM» здесь не меняется — показываем сохранённый
            f.setCrmClient(v.company() == null ? null : v.company().getCrmClient());
            return settingsPage(model, v, f);
        }
    }

    private String settingsPage(Model model, Viewer v, SettingsForm f) {
        AdminPage.head(model, "settings", "Настройки", v.isAll() ? "Выберите компанию в шапке, чтобы изменить её настройки" : v.scopeName());
        model.addAttribute("f", f);
        model.addAttribute("crmOn", crm.enabled());
        model.addAttribute("crmLast", crm.lastOk());
        model.addAttribute("crmError", crm.lastError());
        return "admin/settings";
    }
}
