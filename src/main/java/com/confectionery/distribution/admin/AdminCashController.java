package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.CompanySettings;
import com.confectionery.distribution.domain.ShortageDecision;
import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.domain.TripStatus;
import com.confectionery.distribution.service.CashReport;
import com.confectionery.distribution.service.CashService;
import com.confectionery.distribution.service.FormException;
import com.confectionery.distribution.service.SettingsService;
import com.confectionery.distribution.service.TripService;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.time.Clock;
import java.time.LocalDate;
import java.time.format.TextStyle;
import java.util.List;
import java.util.Locale;

/**
 * Приём рейса вечером: оператор пересчитывает наличные и сверяет Kaspi, кладовщик принимает товар. Недостача больше
 * допуска — решение директора: на экспедитора или списать с причиной.
 */
@Controller
@RequiredArgsConstructor
public class AdminCashController {

    private final AdminContext ctx;
    private final TripService trips;
    private final CashService cash;
    private final CashReport report;
    private final SettingsService settings;
    private final Fmt fmt;
    private final Clock clock;

    @GetMapping("/admin/cash")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        List<Trip> list = trips.current(v.companyId());
        AdminPage.head(model, "cash", "Приём кассы", v.scopeName() + " · " + fmt.longDay(LocalDate.now(clock)));
        model.addAttribute("decide", list.stream().filter(Trip::isShortageWaiting).toList());
        model.addAttribute("waiting", list.stream().filter(t -> t.isWaitingCash() && !t.isShortageWaiting()).toList());
        model.addAttribute("onRoad", list.stream().filter(t -> t.isOpen() && !t.isWaitingCash() && !t.isShortageWaiting()).toList());
        model.addAttribute("closed", list.stream().filter(t -> t.getStatus() == TripStatus.CLOSED).toList());
        model.addAttribute("onHands", list.stream().filter(t -> t.getStatus().cashOnHands()).mapToLong(Trip::getCash).sum());
        return "admin/cash/list";
    }

    @GetMapping("/admin/cash/{id}")
    public String accept(@PathVariable Long id, Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        Trip t = trips.get(id);
        CompanySettings st = settings.of(t.getCompanyId());
        LocalDate today = LocalDate.now(clock);
        AdminPage.head(model, "cash", "Приём кассы · " + t.getExpeditor().getName(),
                "рейс " + t.getNumber() + " · " + t.getVehicle().getPlate() + " · " + fmt.day(t.getDate()));
        model.addAttribute("t", t);
        model.addAttribute("st", st);
        model.addAttribute("canDecide", CashService.canDecide(st, v.role()));
        model.addAttribute("expDebt", report.expeditorDebts(t.getCompanyId()).getOrDefault(t.getExpeditor().getId(), 0L));
        model.addAttribute("month", today.getMonth().getDisplayName(TextStyle.FULL_STANDALONE, Locale.forLanguageTag("ru")));
        model.addAttribute("monthRows", report.build(t.getCompanyId(), today.withDayOfMonth(1), today, null).rows());
        model.addAttribute("today", trips.current(t.getCompanyId()).stream().filter(x -> x.getHandover() != null || x.isWaitingCash()).toList());
        return "admin/cash/accept";
    }

    @PostMapping("/admin/cash/{id}")
    public String doAccept(@PathVariable Long id, @RequestParam String counted,
                           @RequestParam(defaultValue = "false") boolean kaspi,
                           @RequestParam(defaultValue = "false") boolean goods,
                           @RequestParam(required = false) String decision,
                           @RequestParam(required = false) String reason, HttpSession session) {
        long sum;
        try {
            sum = Long.parseLong(counted.replaceAll("[^0-9]", ""));
        } catch (NumberFormatException e) {
            ctx.toast(session, "Введите пересчитанную сумму наличных");
            return "redirect:/admin/cash/" + id;
        }
        Viewer v = ctx.viewer(session);
        Trip t;
        try {
            t = cash.accept(id, sum, kaspi, goods, decision, reason, v.actor(), v.role());
        } catch (FormException e) {
            ctx.toast(session, e.getMessage());
            return "redirect:/admin/cash/" + id;
        }
        if (t.getStatus() == TripStatus.CLOSED) {
            ctx.toast(session, "Рейс " + t.getNumber() + " закрыт · " + closedText(t));
            return "redirect:/admin/cash";
        }
        if (t.isShortageWaiting()) {
            ctx.toast(session, "Недостача " + fmt.money(-t.getCashDiff()) + " больше допуска — рейс закроет директор или владелец");
            return "redirect:/admin/cash";
        }
        ctx.toast(session, "Сумма записана. Рейс закроется, когда сверен Kaspi и принят товар");
        return "redirect:/admin/cash/" + id;
    }

    private String closedText(Trip t) {
        Long diff = t.getCashDiff();
        if (diff == null || diff == 0) return "касса сошлась";
        if (diff > 0) return "излишек " + fmt.money(diff);
        ShortageDecision d = t.getHandover().getShortageDecision();
        String sum = "недостача " + fmt.money(-diff);
        if (d == ShortageDecision.EXPEDITOR) return sum + " записана на " + t.getExpeditor().getName();
        if (d == ShortageDecision.WRITE_OFF) return sum + " списана: " + t.getHandover().getShortageReason();
        return sum + " в пределах допуска";
    }
}
