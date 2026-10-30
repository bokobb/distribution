package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.Trip;
import com.confectionery.distribution.service.DeliveryService;
import com.confectionery.distribution.service.NotFoundException;
import com.confectionery.distribution.service.OrderService;
import com.confectionery.distribution.service.TripService;
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
import org.springframework.web.bind.annotation.PathVariable;

import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Controller
@RequiredArgsConstructor
public class AdminTripController {

    private final AdminContext ctx;
    private final TripService trips;
    private final DeliveryService deliveries;
    private final Fmt fmt;
    private final OrderService orders;
    private final com.confectionery.distribution.service.ApprovalService approvals;
    private final tools.jackson.databind.ObjectMapper json;
    private final Clock clock;

    @GetMapping("/admin/trips")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        LocalDate today = LocalDate.now(clock);
        AdminPage.head(model, "trips", "Рейсы", fmt.cap(fmt.longDay(today)) + " · " + v.scopeName());
        List<Trip> list = trips.forPage(v.companyId());
        // итоги — по рейсам сегодня и не закрытым с прошлых дней (рейсы на завтра ещё не начались)
        List<Trip> day = list.stream().filter(t -> !t.getDate().isAfter(today)).toList();
        model.addAttribute("earlier", day.stream().filter(t -> t.getDate().isBefore(today)).count());
        model.addAttribute("trips", list);
        model.addAttribute("day", day);
        model.addAttribute("closed", day.stream().filter(t -> !t.isOpen()).count());
        model.addAttribute("handed", day.stream().mapToInt(Trip::getHanded).sum());
        model.addAttribute("stops", day.stream().mapToInt(Trip::getStops).sum());
        model.addAttribute("refused", day.stream().mapToLong(t -> t.getOrders().stream().filter(o -> o.getStatus() == OrderStatus.REFUSED).count()).sum());
        model.addAttribute("proofs", day.stream().mapToInt(Trip::getProofs).sum());
        model.addAttribute("cash", day.stream().mapToLong(Trip::getCash).sum());
        model.addAttribute("cashIn", day.stream().filter(t -> !t.isOpen()).mapToLong(t -> t.getCashCounted() == null ? t.getCash() : t.getCashCounted()).sum());
        model.addAttribute("cashOut", day.stream().filter(Trip::isOpen).mapToLong(Trip::getCash).sum());
        // ждут отгрузки — новые, собранные и ждущие разрешения за любой день
        Map<Company, List<Order>> next = new java.util.LinkedHashMap<>();
        orders.waiting().stream()
                .filter(o -> v.companyId() == null || v.companyId().equals(o.getCompanyId()))
                .sorted(java.util.Comparator.comparing(o -> o.getCompany().getName()))
                .forEach(o -> next.computeIfAbsent(o.getCompany(), k -> new java.util.ArrayList<>()).add(o));
        model.addAttribute("next", next);
        model.addAttribute("nextCount", next.values().stream().mapToInt(List::size).sum());
        model.addAttribute("today", today);
        return "admin/trips/list";
    }

    /** Точка рейса: получено за заказ, в счёт старого долга, негодного забрано (шт), чем платили. */
    public record Stop(Order o, long paid, long old, int ret, String methods) {
    }

    @GetMapping("/admin/trips/{id}")
    public String view(@PathVariable Long id, Model model, HttpSession session) {
        Trip t = trips.get(id);
        AdminPage.head(model, "trips", "Рейс " + t.getNumber(), fmt.dot(t.getExpeditor().getName(), fmt.longDay(t.getDate()), t.getCompany().getName()));
        model.addAttribute("t", t);
        model.addAttribute("rows", OrderService.pickList(t.getOrders()));
        List<Order> stops = t.getTripOrders().stream().sorted(java.util.Comparator.comparingInt(com.confectionery.distribution.domain.TripOrder::getPosition))
                .map(com.confectionery.distribution.domain.TripOrder::getOrder).toList();
        model.addAttribute("stops", stops.stream().map(o -> {
            List<com.confectionery.distribution.domain.Payment> pay = t.getPayments().stream().filter(p -> o.equals(p.getOrder())).toList();
            return new Stop(o, pay.stream().mapToLong(com.confectionery.distribution.domain.Payment::getAmount).sum(),
                    t.getPayments().stream().filter(p -> p.isOldDebt() && o.getOutlet().equals(p.getOutlet()))
                            .mapToLong(com.confectionery.distribution.domain.Payment::getAmount).sum(),
                    t.getReturns().stream().filter(r -> o.equals(r.getOrder())).mapToInt(com.confectionery.distribution.domain.ProductReturn::getQty).sum(),
                    pay.stream().map(p -> p.getMethod().getLabel().toLowerCase()).distinct().collect(java.util.stream.Collectors.joining(", ")));
        }).toList());
        Map<Long, String> notes = approvals.orderNotes(stops);
        model.addAttribute("notes", notes);
        List<Map<String, Object>> points = new java.util.ArrayList<>();
        for (int i = 0; i < stops.size(); i++) {
            Order o = stops.get(i);
            if (o.getOutlet().getLat() == null || o.getOutlet().getLng() == null) continue;
            points.add(Map.of("n", i + 1, "lat", o.getOutlet().getLat(), "lng", o.getOutlet().getLng(), "name", o.getOutlet().getName(),
                    "state", o.getStatus().getLabel(), "done", o.getStatus().delivered()));
        }
        model.addAttribute("points", json.writeValueAsString(points));
        model.addAttribute("loadedQty", stops.stream().mapToInt(Order::getQty).sum());
        model.addAttribute("handedQty", stops.stream().filter(o -> o.getDelivery() != null && o.getStatus().delivered())
                .mapToInt(o -> o.getDelivery().getItems().stream().mapToInt(com.confectionery.distribution.domain.DeliveryItem::getQty).sum()).sum());
        model.addAttribute("underpay", stops.stream().filter(o -> "недоплата ждёт решения".equals(notes.get(o.getId())))
                .mapToLong(o -> Math.max(0, o.getDeliveredTotal() - (o.getReturnLines().isEmpty() ? 0 : o.getReturnTotal())
                        - t.getPayments().stream().filter(p -> o.equals(p.getOrder())).mapToLong(com.confectionery.distribution.domain.Payment::getAmount).sum())).sum());
        return "admin/trips/view";
    }

    /** Общая накладная рейса: отгружено, чистый и испорченный возврат — та же страница, что из «Заказов». */
    @GetMapping("/admin/trips/{id}/invoice")
    public String invoice(@PathVariable Long id, Model model) {
        Trip t = trips.get(id);
        AdminOrderController.invoiceModel(t.getOrders(), true, model, fmt);
        return "admin/orders/invoices";
    }

    /** Подпись получателя или фото накладной к выдаче — ссылка в точке рейса и в карточке заказа. */
    @GetMapping("/admin/trips/proof/{uuid}")
    public ResponseEntity<Resource> proof(@PathVariable UUID uuid) {
        Path file = deliveries.proofFile(uuid).orElseThrow(NotFoundException::new);
        MediaType type = file.toString().endsWith(".png") ? MediaType.IMAGE_PNG : MediaType.IMAGE_JPEG;
        return ResponseEntity.ok().contentType(type)
                .cacheControl(CacheControl.maxAge(Duration.ofDays(1)).cachePrivate()).body(new FileSystemResource(file));
    }
}
