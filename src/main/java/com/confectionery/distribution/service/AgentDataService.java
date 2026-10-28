package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.OutletRepository;
import com.confectionery.distribution.repository.ProductRepository;
import com.confectionery.distribution.repository.RouteRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;

/**
 * Всё, что нужно торговому агенту на телефоне для работы без сети: настройки компании, товары с ценами на
 * сегодня, его маршруты с магазинами по порядку обхода, долги магазинов, его визиты и заказы за сегодня, а для
 * карты — остальные магазины компании (только название, адрес и точка, без долгов). Телефон забирает это целиком при
 * синхронизации и заменяет прежнее. Компания — из входа (TenantContext), чужое сюда не попадает.
 */
@Service
@RequiredArgsConstructor
public class AgentDataService {

    private final RouteRepository routes;
    private final OutletRepository allOutlets;
    private final ProductRepository products;
    private final CatalogService catalog;
    private final DebtService debts;
    private final SettingsService settings;
    private final VisitService visits;
    private final MobileOrderService orders;
    private final Clock clock;

    public record Settings(int visitRadius, boolean shelfPhotoRequired, boolean refuseReasonRequired, int deliveryDays,
                           boolean allowCredit, boolean approvalOverLimit, boolean agentDiscount, boolean acceptKaspi,
                           int gpsInterval) {
    }

    public record ProductDto(Long id, String name, String category, String unit, int perBox, String barcode,
                             long wholesale, long retail) {
    }

    /** days — дни обхода по ISO: 1 — понедельник … 7 — воскресенье; outlets — id магазинов по порядку. */
    public record RouteDto(Long id, String name, String region, List<Integer> days, List<Long> outlets) {
    }

    /** priceKind — по какому прайсу магазин берёт (WHOLESALE, RETAIL); долг и просрочка — на сегодня. */
    public record OutletDto(Long id, UUID uuid, String name, String legal, String owner, String phone, String phone2,
                            String address, String landmark, Double lat, Double lng, String priceKind, long creditLimit,
                            int paymentDays, String status, long debt, long overdue, LocalDate lastPaymentDate,
                            long lastPaymentSum) {
    }

    /** Магазин другого торгового — для карты агента; region — филиал его маршрута. */
    public record PlaceDto(Long id, String name, String address, String landmark, double lat, double lng, String region) {
    }

    /** others — магазины компании не из маршрутов агента, у которых есть точка на карте. */
    public record AgentData(LocalDate date, LocalDateTime syncedAt, Settings settings, List<ProductDto> products,
                            List<RouteDto> routes, List<OutletDto> outlets, List<VisitService.VisitOut> visits,
                            List<MobileOrderService.OrderOut> orders, List<PlaceDto> others) {
    }

    /** Магазин для телефона; долг и последняя оплата — если заполнены (DebtService). */
    public static OutletDto outlet(Outlet o) {
        return new OutletDto(o.getId(), o.getUuid(), o.getName(), o.getLegal(), o.getOwner(), o.getPhone(), o.getPhone2(),
                o.getAddress(), o.getLandmark(), o.getLat(), o.getLng(),
                o.getPriceType() == null ? PriceKind.WHOLESALE.name() : o.getPriceType().getCode().name(),
                o.getCreditLimit(), o.getPaymentDays(), o.getStatus().name(), o.getDebt(), o.getOverdue(),
                o.getLastPaymentDate(), o.getLastPaymentSum());
    }

    @Transactional(readOnly = true)
    public AgentData of(Long agentId, Long companyId) {
        CompanySettings s = settings.of(companyId);
        List<Route> mine = routes.findAllByOrderByNameAsc().stream()
                .filter(r -> r.isActive() && r.getAgent() != null && r.getAgent().getId().equals(agentId)).toList();

        Map<Long, Outlet> outlets = new LinkedHashMap<>();
        List<RouteDto> routeDtos = new ArrayList<>();
        for (Route r : mine) {
            List<Long> ids = new ArrayList<>();
            for (Outlet o : r.getOutlets()) {
                if (o.getStatus() == OutletStatus.CLOSED) continue;
                outlets.putIfAbsent(o.getId(), o);
                ids.add(o.getId());
            }
            List<Integer> days = Arrays.stream(DayOfWeek.values()).filter(r::visitsOn).map(DayOfWeek::getValue).toList();
            routeDtos.add(new RouteDto(r.getId(), r.getName(), r.getRegion() == null ? null : r.getRegion().getName(), days, ids));
        }
        debts.fill(outlets.values());

        List<Product> active = products.findAllByOrderByNameAsc().stream().filter(Product::isActive).toList();
        catalog.fillPrices(active);

        LocalDate today = LocalDate.now(clock);
        return new AgentData(today, LocalDateTime.now(clock).truncatedTo(ChronoUnit.SECONDS),
                new Settings(s.getVisitRadius(), s.isShelfPhotoRequired(), s.isRefuseReasonRequired(), s.getDeliveryDays(),
                        s.isAllowCredit(), s.isApprovalOverLimit(), s.isAgentDiscount(), s.isAcceptKaspi(), s.getGpsInterval()),
                active.stream().map(p -> new ProductDto(p.getId(), p.getName(), p.getCategory(), p.getUnit(), p.getPerBox(),
                        p.getBarcode(), p.getWholesale(), p.getRetail())).toList(),
                routeDtos,
                outlets.values().stream().map(AgentDataService::outlet).toList(),
                visits.of(agentId, today), orders.of(agentId, today), others(outlets.keySet()));
    }

    private List<PlaceDto> others(Set<Long> mine) {
        return allOutlets.findAllByOrderByNameAsc().stream()
                .filter(o -> !mine.contains(o.getId()) && o.getStatus() != OutletStatus.CLOSED && o.getLat() != null && o.getLng() != null)
                .map(o -> new PlaceDto(o.getId(), o.getName(), o.getAddress(), o.getLandmark(), o.getLat(), o.getLng(),
                        o.getRegion() == null ? null : o.getRegion().getName()))
                .toList();
    }
}
