package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.service.MapService;
import com.confectionery.distribution.service.NotFoundException;
import com.confectionery.distribution.service.VisitService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** Карта: магазины и пути торговых и экспедиторов за день. Данные страница берёт из /admin/map/data. */
@Controller
@RequiredArgsConstructor
public class AdminMapController {

    private final AdminContext ctx;
    private final MapService map;
    private final VisitService visits;
    private final Fmt fmt;
    private final Clock clock;

    @GetMapping("/admin/map")
    public String page(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
                       @RequestParam(name = "who", required = false) List<Long> who,
                       Model model, HttpSession session, HttpServletRequest request) {
        Viewer v = ctx.viewer(session);
        LocalDate day = date == null ? LocalDate.now(clock) : date;
        List<Long> sel = who == null ? List.of() : who;
        List<MapService.Who> people = map.people(v.companyId());
        AdminPage.head(model, "map", "Карта", v.scopeName() + " · " + fmt.longDay(day));
        model.addAttribute("date", day);
        model.addAttribute("agents", people.stream().filter(p -> p.role() == Role.AGENT).toList());
        model.addAttribute("expeditors", people.stream().filter(p -> p.role() == Role.EXPEDITOR).toList());
        model.addAttribute("sel", sel);
        model.addAttribute("chosen", people.stream().filter(p -> sel.contains(p.id())).toList());
        model.addAttribute("link", new QueryLink(request));
        return "admin/map";
    }

    /** Фото полки к визиту — ссылка во всплывающей подписи визита. */
    @GetMapping("/admin/map/photo/{uuid}")
    public ResponseEntity<Resource> photo(@PathVariable UUID uuid) {
        Path file = visits.photoFile(uuid).orElseThrow(NotFoundException::new);
        return ResponseEntity.ok().contentType(MediaType.IMAGE_JPEG)
                .cacheControl(CacheControl.maxAge(Duration.ofDays(1)).cachePrivate()).body(new FileSystemResource(file));
    }

    @GetMapping("/admin/map/data")
    @ResponseBody
    public MapService.Day data(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
                               @RequestParam(name = "who", required = false) List<Long> who, HttpSession session) {
        return map.day(ctx.viewer(session).companyId(), date == null ? LocalDate.now(clock) : date, who);
    }
}
