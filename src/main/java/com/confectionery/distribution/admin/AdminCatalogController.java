package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Product;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.service.CatalogService;
import com.confectionery.distribution.service.CompanyService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.Forms;
import com.confectionery.distribution.service.PriceListXlsx;
import com.confectionery.distribution.service.SettingsService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * «Товары и прайс». С 04.11.2026 у товара одна цена продажи (опт = розница) рядом с ценой CRM и наценкой, %:
 * директор и владелец меняют цену или наценку прямо в таблице, «Поставить всем» считает цены по общей наценке
 * (с ней же новый товар из CRM получает цену сам). Оператор только смотрит.
 * С 09.11.2026 «Скачать прайс» — Excel для магазинов, его скачивает каждый, кто видит раздел.
 */
@Controller
@RequiredArgsConstructor
public class AdminCatalogController {

    private static final Pattern PRICE = Pattern.compile("price_(\\d{1,18})");

    private final AdminContext ctx;
    private final CatalogService catalog;
    private final CompanyService companies;
    private final Fmt fmt;
    private final com.confectionery.distribution.service.CrmSync crm;
    private final SettingsService settings;
    private final PriceListXlsx priceList;
    private final Clock clock;

    @GetMapping("/admin/products")
    public String products(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        // в режиме «Все компании» каталог показываем по первой компании: у каждой свой прайс
        Company first = v.isAll() ? companies.first() : null;
        List<Product> list = catalog.products(v.isAll() ? (first == null ? -1L : first.getId()) : v.companyId());
        Map<String, List<Product>> byCat = list.stream()
                .collect(Collectors.groupingBy(Product::getCategory, TreeMap::new, Collectors.toList()));
        AdminPage.head(model, "products", "Товары и прайс",
                (v.isAll() ? (first == null ? "—" : first.getName()) + " (у каждой компании свой прайс)" : v.scopeName())
                        + " · " + fmt.plural(list.size(), "товар", "товара", "товаров"));
        model.addAttribute("byCat", byCat);
        model.addAttribute("products", list.stream().sorted(java.util.Comparator.comparing(Product::getCategory).thenComparing(Product::getName)).toList());
        model.addAttribute("fromCrm", list.stream().filter(p -> p.getCrmCode() != null).count());
        model.addAttribute("notCrm", list.stream().filter(p -> p.getCrmCode() == null).map(Product::getName).toList());
        model.addAttribute("crmOn", crm.enabled());
        model.addAttribute("crmAt", crm.lastOk());
        model.addAttribute("canEdit", canEdit(v));
        model.addAttribute("markup", settings.of(v.isAll() ? (first == null ? null : first.getId()) : v.companyId()).getPriceMarkup());
        model.addAttribute("noPrice", list.stream().filter(p -> p.isActive() && p.getPrice() == 0).count());
        model.addAttribute("inPriceList", PriceListXlsx.rows(list).size());
        return "admin/products/list";
    }

    /** Прайс для магазинов в Excel: цены на сегодня той же компании, что на странице («Все компании» — первая). */
    @GetMapping("/admin/products/price.xlsx")
    public ResponseEntity<byte[]> priceList(HttpSession session) {
        Viewer v = ctx.require(session, "products");
        Company c = v.isAll() ? companies.first() : v.company();
        List<Product> list = c == null ? List.of() : catalog.products(c.getId());
        LocalDate today = LocalDate.now(clock);
        String name = c == null ? "" : c.getName();
        byte[] file = priceList.write(name, c == null ? null : c.getPhone(), today, list);
        String fileName = ("Прайс " + name + " " + PriceListXlsx.DAY.format(today)).replaceAll("[\\\\/:*?\"<>|]", " ")
                .replaceAll("\\s+", " ").trim() + ".xlsx";
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment().filename(fileName, StandardCharsets.UTF_8).build().toString())
                .header(HttpHeaders.CACHE_CONTROL, "no-store")
                .contentType(MediaType.parseMediaType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                .body(file);
    }

    /** Цены (поля price_{id}, пустое — без изменений) и общая наценка. Неверное число — ничего не сохраняется. */
    @PostMapping("/admin/products/prices")
    public String savePrices(@RequestParam Map<String, String> form, HttpSession session) {
        Viewer v = ctx.require(session, "products");
        if (!canEdit(v)) throw new AccessDeniedException("Цены меняют директор и владелец — в своей компании");
        try {
            int markup = Forms.number(form.get("markup"), "Наценка, %", 0, 500);
            Map<Long, Long> prices = new HashMap<>();
            for (Map.Entry<String, String> e : form.entrySet()) {
                Matcher m = PRICE.matcher(e.getKey());
                if (!m.matches() || e.getValue() == null || e.getValue().isBlank()) continue;
                long price = Forms.money(e.getValue(), "Цена");
                if (price <= 0 || price > 100_000_000) throw new FormException("Цена — от 1 до 100 000 000 ₸");
                prices.put(Long.parseLong(m.group(1)), price);
            }
            settings.saveMarkup(v.companyId(), markup);
            int n = catalog.savePrices(v.companyId(), prices);
            ctx.toast(session, n == 0 ? "Цены не менялись · наценка " + markup + " %"
                    : "Сохранено цен: " + n + " — действуют с сегодня");
        } catch (FormException e) {
            ctx.toast(session, e.getMessage() + " — ничего не сохранено");
        }
        return "redirect:/admin/products";
    }

    /** Цены меняют директор и владелец, выбрав компанию в шапке («Все компании» — только смотреть). */
    private static boolean canEdit(Viewer v) {
        return v != null && !v.isAll() && (v.role() == Role.DIRECTOR || v.role() == Role.SUPER_ADMIN);
    }
}
