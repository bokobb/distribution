package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Product;
import com.confectionery.distribution.stub.StubStore;
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
    private final StubStore store;

    @GetMapping("/admin/products")
    public String products(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Product> list = store.products(v.companyId());
        Map<String, List<Product>> byCat = list.stream()
                .collect(Collectors.groupingBy(Product::getCategory, TreeMap::new, Collectors.toList()));
        AdminPage.head(model, "products", "Товары и прайс",
                (v.isAll() ? store.companies().get(0).getName() + " (у каждой компании свой прайс)" : v.scopeName())
                        + " · " + list.size() + " товаров");
        model.addAttribute("byCat", byCat);
        model.addAttribute("fromCrm", list.stream().filter(p -> p.getCrmCode() != null).count());
        return "admin/products/list";
    }
}
