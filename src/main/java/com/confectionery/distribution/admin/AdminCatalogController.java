package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Product;
import com.confectionery.distribution.service.CatalogService;
import com.confectionery.distribution.service.CompanyService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

@Controller
@RequiredArgsConstructor
public class AdminCatalogController {

    private final AdminContext ctx;
    private final CatalogService catalog;
    private final CompanyService companies;
    private final Fmt fmt;
    private final com.confectionery.distribution.service.CrmSync crm;

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
        return "admin/products/list";
    }
}
