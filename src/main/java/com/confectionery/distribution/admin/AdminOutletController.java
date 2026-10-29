package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.OutletStatus;
import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.repository.PriceTypeRepository;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.NotFoundException;
import com.confectionery.distribution.service.OutletForm;
import com.confectionery.distribution.service.OutletService;
import com.confectionery.distribution.service.RegionService;
import com.confectionery.distribution.service.SettingsService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.nio.file.Path;
import java.time.Duration;
import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Controller
@RequiredArgsConstructor
public class AdminOutletController {

    private final AdminContext ctx;
    private final OutletService outlets;
    private final RegionService regions;
    private final com.confectionery.distribution.service.StaffService staff;
    private final SettingsService settings;
    private final PriceTypeRepository priceTypes;
    private final Fmt fmt;

    @GetMapping("/admin/outlets")
    public String list(@RequestParam(required = false) OutletStatus status,
                       @RequestParam(required = false) Long region,
                       @RequestParam(required = false) String q,
                       Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Outlet> all = outlets.list(v.companyId());
        Map<OutletStatus, Long> counts = new EnumMap<>(OutletStatus.class);
        for (Outlet o : all) counts.merge(o.getStatus(), 1L, Long::sum);
        String needle = q == null ? "" : q.trim().toLowerCase(Locale.ROOT);
        List<Outlet> list = all.stream()
                .filter(o -> status == null || o.getStatus() == status)
                .filter(o -> region == null || (o.getRegion() != null && region.equals(o.getRegion().getId())))
                .filter(o -> needle.isEmpty() || Stream.of(o.getName(), o.getOwner(), o.getPhone(), o.getAddress()).filter(Objects::nonNull).collect(Collectors.joining(" "))
                        .toLowerCase(Locale.ROOT).contains(needle))
                .sorted(Comparator.comparing(Outlet::getName)).toList();
        AdminPage.head(model, "outlets", "Магазины", v.scopeName() + " · " + fmt.plural(all.size(), "точка", "точки", "точек"));
        model.addAttribute("outlets", list);
        model.addAttribute("counts", counts);
        model.addAttribute("total", all.size());
        model.addAttribute("statuses", OutletStatus.values());
        model.addAttribute("status", status);
        model.addAttribute("regions", regions.regions());
        model.addAttribute("region", region);
        model.addAttribute("q", q);
        return "admin/outlets/list";
    }

    @GetMapping("/admin/outlets/{id}")
    public String view(@PathVariable Long id, Model model, HttpSession session) {
        Outlet o = outlets.get(id);
        AdminPage.head(model, "outlets", o.getName(), Stream.of(o.getLegal(), o.getAddress()).filter(Objects::nonNull).collect(Collectors.joining(" · ")));
        model.addAttribute("o", o);
        model.addAttribute("orders", outlets.ordersOf(o));
        model.addAttribute("payments", outlets.paymentsOf(o));
        model.addAttribute("returns", outlets.returnsOf(o));
        return "admin/outlets/view";
    }

    /** Фото фасада, которое снял агент. */
    @GetMapping("/admin/outlets/{id}/photo")
    public ResponseEntity<Resource> photo(@PathVariable Long id) {
        Path file = outlets.facadeFile(outlets.get(id)).orElseThrow(NotFoundException::new);
        return ResponseEntity.ok().contentType(MediaType.IMAGE_JPEG)
                .cacheControl(CacheControl.maxAge(Duration.ofDays(1)).cachePrivate()).body(new FileSystemResource(file));
    }

    @GetMapping("/admin/outlets/new")
    public String create(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        if (v.isAll()) {
            ctx.toast(session, "Выберите компанию в шапке: магазин добавляется в одну компанию");
            return "redirect:/admin/outlets";
        }
        OutletForm f = new OutletForm();
        f.setCreditLimit(String.valueOf(settings.of(v.companyId()).getDefaultCreditLimit()));
        f.setPaymentDays("7");
        priceTypes.findByCompanyIdAndCode(v.companyId(), PriceKind.WHOLESALE).ifPresent(t -> f.setPriceTypeId(t.getId()));
        return form(model, f, v.companyId(), v.scopeName());
    }

    @GetMapping("/admin/outlets/{id}/edit")
    public String edit(@PathVariable Long id, Model model) {
        Outlet o = outlets.get(id);
        return form(model, OutletForm.of(o), o.getCompanyId(), o.getName());
    }

    @PostMapping("/admin/outlets/save")
    public String save(@ModelAttribute("f") OutletForm f, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        try {
            Outlet o = outlets.save(f, v.companyId(), v.who());
            ctx.toast(session, "«" + o.getName() + "» — сохранено");
            return "redirect:/admin/outlets/" + o.getId();
        } catch (FormException e) {
            model.addAttribute("error", e.getMessage());
            Outlet o = f.getId() == null ? null : outlets.get(f.getId());
            return form(model, f, o == null ? v.companyId() : o.getCompanyId(), o == null ? v.scopeName() : o.getName());
        }
    }

    /** Форма магазина: торговые, районы и типы цен — только компании этого магазина. */
    private String form(Model model, OutletForm f, Long companyId, String sub) {
        AdminPage.head(model, "outlets", f.getId() == null ? "Новый магазин" : "Изменить магазин", sub);
        model.addAttribute("f", f);
        model.addAttribute("agents", staff.employees(companyId).stream()
                .filter(e -> e.getRole() == com.confectionery.distribution.domain.Role.AGENT && e.isActive()).toList());
        model.addAttribute("regions", regions.regions().stream().filter(r -> r.getCompanyId().equals(companyId)).toList());
        model.addAttribute("priceTypes", priceTypes.findByCompanyIdOrderByIdAsc(companyId));
        return "admin/outlets/form";
    }

    @PostMapping("/admin/outlets/{id}/approve")
    public String approve(@PathVariable Long id, HttpSession session) {
        Outlet o = outlets.approve(id);
        ctx.toast(session, o.getName() + " — проверен, работает");
        return "redirect:/admin/outlets/" + id;
    }
}
