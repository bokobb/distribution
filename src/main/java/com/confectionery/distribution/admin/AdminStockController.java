package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Receipt;
import com.confectionery.distribution.domain.ReceiptLine;
import com.confectionery.distribution.stub.StubStore;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.server.ResponseStatusException;

import java.util.HashMap;
import java.util.Map;

import static org.springframework.http.HttpStatus.NOT_FOUND;

@Controller
@RequiredArgsConstructor
public class AdminStockController {

    private final AdminContext ctx;
    private final StubStore store;

    @GetMapping("/admin/stock")
    public String stock(@RequestParam(defaultValue = "stock") String tab, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "stock", "Склад и приходы",
                v.isAll() ? store.companies().get(0).getName() + " (в режиме «Все компании» — склад первой)" : v.scopeName());
        model.addAttribute("tab", "receipts".equals(tab) ? "receipts" : "stock");
        model.addAttribute("rows", store.stock(v.companyId()));
        model.addAttribute("receipts", store.receipts(v.companyId()));
        return "admin/stock/list";
    }

    @GetMapping("/admin/stock/receipts/{id}")
    public String receipt(@PathVariable Long id, Model model, HttpSession session) {
        Receipt r = own(id, session);
        AdminPage.head(model, "stock", "Приход " + r.getNumber(), r.getSource().getLabel() + " · " + r.getBasis());
        model.addAttribute("r", r);
        return "admin/stock/receipt";
    }

    /** Подтвердить приход: фактические количества из полей qty_{productId}. */
    @PostMapping("/admin/stock/receipts/{id}")
    public String confirm(@PathVariable Long id, HttpServletRequest req, HttpSession session) {
        Receipt r = own(id, session);
        Map<Long, Integer> actual = new HashMap<>();
        for (ReceiptLine l : r.getLines()) {
            String s = req.getParameter("qty_" + l.getProduct().getId());
            if (s != null && s.matches("\\d{1,6}")) actual.put(l.getProduct().getId(), Integer.parseInt(s));
        }
        store.confirmReceipt(id, actual, ctx.viewer(session).me().getName());
        ctx.toast(session, "Приход " + r.getNumber() + " принят на склад");
        return "redirect:/admin/stock/receipts/" + id;
    }

    private Receipt own(Long id, HttpSession session) {
        Receipt r = store.receipt(id);
        Viewer v = ctx.viewer(session);
        if (r == null || (!v.isAll() && !r.getCompany().getId().equals(v.companyId())))
            throw new ResponseStatusException(NOT_FOUND);
        return r;
    }
}
