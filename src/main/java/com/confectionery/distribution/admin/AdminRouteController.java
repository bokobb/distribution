package com.confectionery.distribution.admin;

import com.confectionery.distribution.stub.StubStore;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
@RequiredArgsConstructor
public class AdminRouteController {

    private final AdminContext ctx;
    private final StubStore store;

    @GetMapping("/admin/routes")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "routes", "Маршруты и регионы", v.scopeName() + " · " + store.routes(v.companyId()).size() + " маршрутов");
        model.addAttribute("regions", store.regions(v.companyId()));
        return "admin/routes/list";
    }
}
