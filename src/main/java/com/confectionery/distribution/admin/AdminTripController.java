package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.stub.StubStore;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.server.ResponseStatusException;

import java.util.Comparator;

import static org.springframework.http.HttpStatus.NOT_FOUND;

@Controller
@RequiredArgsConstructor
public class AdminTripController {

    private final AdminContext ctx;
    private final StubStore store;
    private final Fmt fmt;

    @GetMapping("/admin/trips")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "trips", "Рейсы", v.scopeName() + " · " + fmt.longDay(store.today()));
        model.addAttribute("trips", store.trips(v.companyId()).stream()
                .sorted(Comparator.comparing((Trip t) -> t.getStatus().ordinal())).toList());
        return "admin/trips/list";
    }

    @GetMapping("/admin/trips/{id}")
    public String view(@PathVariable Long id, Model model, HttpSession session) {
        Trip t = own(store, ctx, id, session);
        AdminPage.head(model, "trips", "Рейс " + t.getNumber(),
                t.getExpeditor().getName() + " · " + t.getVehicle().getModel() + " " + t.getVehicle().getPlate());
        model.addAttribute("t", t);
        model.addAttribute("rows", store.pickList(t.getOrders()));
        return "admin/trips/view";
    }

    static Trip own(StubStore store, AdminContext ctx, Long id, HttpSession session) {
        Trip t = store.trip(id);
        Viewer v = ctx.viewer(session);
        if (t == null || (!v.isAll() && !t.getCompany().getId().equals(v.companyId())))
            throw new ResponseStatusException(NOT_FOUND);
        return t;
    }
}
