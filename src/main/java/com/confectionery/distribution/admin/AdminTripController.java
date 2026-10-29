package com.confectionery.distribution.admin;

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
import java.util.UUID;

@Controller
@RequiredArgsConstructor
public class AdminTripController {

    private final AdminContext ctx;
    private final TripService trips;
    private final DeliveryService deliveries;
    private final Fmt fmt;
    private final Clock clock;

    @GetMapping("/admin/trips")
    public String list(Model model, HttpSession session) {
        Viewer v = ctx.viewer(session);
        AdminPage.head(model, "trips", "Рейсы", v.scopeName() + " · " + fmt.longDay(LocalDate.now(clock)));
        model.addAttribute("trips", trips.forPage(v.companyId()));
        return "admin/trips/list";
    }

    @GetMapping("/admin/trips/{id}")
    public String view(@PathVariable Long id, Model model, HttpSession session) {
        Trip t = trips.get(id);
        AdminPage.head(model, "trips", "Рейс " + t.getNumber(),
                t.getExpeditor().getName() + " · " + t.getVehicle().getModel() + " " + t.getVehicle().getPlate());
        model.addAttribute("t", t);
        model.addAttribute("rows", OrderService.pickList(t.getOrders()));
        return "admin/trips/view";
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
