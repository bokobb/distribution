package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.RouteService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
@RequiredArgsConstructor
public class AdminRouteController {

    private final AdminContext ctx;
    private final RouteService routes;
    private final Fmt fmt;

    @GetMapping("/admin/routes")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "routes", "Маршруты и регионы", v.scopeName() + " · " + fmt.plural(routes.routes().size(), "маршрут", "маршрута", "маршрутов"));
        model.addAttribute("regions", routes.regions());
        return "admin/routes/list";
    }
}
