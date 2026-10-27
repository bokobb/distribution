package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import com.confectionery.distribution.stub.StubStore;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.List;

/** Приём рейса вечером: оператор пересчитывает наличные и сверяет Kaspi, кладовщик принимает товар. */
@Controller
@RequiredArgsConstructor
public class AdminCashController {

    private final AdminContext ctx;
    private final StubStore store;
    private final Fmt fmt;

    @GetMapping("/admin/cash")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Trip> trips = store.trips(v.companyId());
        AdminPage.head(model, "cash", "Приём кассы", v.scopeName() + " · " + fmt.longDay(store.today()));
        model.addAttribute("waiting", trips.stream().filter(t -> t.getStatus() == TripStatus.RETURNED).toList());
        model.addAttribute("onRoad", trips.stream().filter(t -> t.getStatus() == TripStatus.ON_ROAD || t.getStatus() == TripStatus.LOADING).toList());
        model.addAttribute("closed", trips.stream().filter(t -> t.getStatus() == TripStatus.CLOSED).toList());
        model.addAttribute("onHands", trips.stream().filter(t -> t.getStatus().cashOnHands()).mapToLong(Trip::getCash).sum());
        return "admin/cash/list";
    }

    @GetMapping("/admin/cash/{id}")
    public String accept(@PathVariable Long id, Model model, HttpSession session) {
        Trip t = AdminTripController.own(store, ctx, id, session);
        AdminPage.head(model, "cash", "Приём рейса " + t.getNumber(),
                t.getExpeditor().getName() + " · " + t.getVehicle().getPlate() + " · " + fmt.day(t.getDate()));
        model.addAttribute("t", t);
        return "admin/cash/accept";
    }

    @PostMapping("/admin/cash/{id}")
    public String doAccept(@PathVariable Long id, @RequestParam String counted,
                           @RequestParam(defaultValue = "false") boolean kaspi,
                           @RequestParam(defaultValue = "false") boolean goods, HttpSession session) {
        Trip t = AdminTripController.own(store, ctx, id, session);
        long sum;
        try {
            sum = Long.parseLong(counted.replaceAll("[^0-9]", ""));
        } catch (NumberFormatException e) {
            ctx.toast(session, "Введите пересчитанную сумму наличных");
            return "redirect:/admin/cash/" + id;
        }
        store.acceptTrip(id, sum, kaspi, goods, ctx.viewer(session).me().getName());
        if (t.getStatus() == TripStatus.CLOSED) {
            Long diff = t.getCashDiff();
            ctx.toast(session, "Рейс " + t.getNumber() + " закрыт" + (diff != null && diff != 0 ? ", разница " + fmt.signed(diff) : ", касса сошлась"));
            return "redirect:/admin/cash";
        }
        ctx.toast(session, "Сумма записана. Рейс закроется, когда сверен Kaspi и принят товар");
        return "redirect:/admin/cash/" + id;
    }
}
