package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.OutletRepository;
import com.confectionery.distribution.repository.ProductRepository;
import com.confectionery.distribution.repository.RouteRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
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
 * сегодня, его маршруты с магазинами по порядку обхода, долги магазинов, его визиты и заказы за сегодня, остальные
 * магазины компании (заказ можно принять в любом — магазин ищут по GPS и поиском; у чужих только название, адрес,
 * владелец, прайс и точка, без долгов и телефонов), последний заказ каждого магазина — «повторить», и сводка по
 * магазинам для карты (последний визит, средний заказ). Телефон
 * забирает это целиком при синхронизации и заменяет прежнее. Компания — из входа (TenantContext), чужое сюда не попадает.
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
    private final OutletCardService cards;
    private final JdbcTemplate jdbc;
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

    /** Магазин другого торгового; region — филиал его маршрута; точки может не быть. status — ACTIVE или PENDING. */
    public record PlaceDto(Long id, String name, String address, String landmark, Double lat, Double lng, String region,
                           String owner, String priceKind, String status) {
    }

    public record ItemDto(Long productId, int qty) {
    }

    /** Последний заказ магазина (не отменённый): день и товары — «Как 21 октября» на телефоне. */
    public record LastOrderDto(Long outletId, LocalDate date, List<ItemDto> items) {
    }

    /**
     * others — магазины компании не из маршрутов агента; stats — последний визит и средний заказ всех магазинов;
     * previousOrders — заказы агента за прошлый рабочий день previousDate (вкладка «Вчера»: доставлены или нет).
     */
    public record AgentData(LocalDate date, LocalDateTime syncedAt, Settings settings, List<ProductDto> products,
                            List<RouteDto> routes, List<OutletDto> outlets, List<VisitService.VisitOut> visits,
                            List<MobileOrderService.OrderOut> orders, List<PlaceDto> others, List<LastOrderDto> lastOrders,
                            List<OutletCardService.StatDto> stats, LocalDate previousDate,
                            List<MobileOrderService.OrderOut> previousOrders) {
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
        LocalDate previous = orders.previousDay(agentId, companyId, today);
        return new AgentData(today, LocalDateTime.now(clock).truncatedTo(ChronoUnit.SECONDS),
                new Settings(s.getVisitRadius(), s.isShelfPhotoRequired(), s.isRefuseReasonRequired(), s.getDeliveryDays(),
                        s.isAllowCredit(), s.isApprovalOverLimit(), s.isAgentDiscount(), s.isAcceptKaspi(), s.getGpsInterval()),
                active.stream().map(p -> new ProductDto(p.getId(), p.getName(), p.getCategory(), p.getUnit(), p.getPerBox(),
                        p.getBarcode(), p.getWholesale(), p.getRetail())).toList(),
                routeDtos,
                outlets.values().stream().map(AgentDataService::outlet).toList(),
                visits.of(agentId, today), orders.of(agentId, today), others(outlets.keySet()), lastOrders(companyId),
                cards.stats(companyId), previous, previous == null ? List.of() : orders.of(agentId, previous));
    }

    private List<PlaceDto> others(Set<Long> mine) {
        return allOutlets.findAllByOrderByNameAsc().stream()
                .filter(o -> !mine.contains(o.getId()) && o.getStatus() != OutletStatus.CLOSED)
                .map(o -> new PlaceDto(o.getId(), o.getName(), o.getAddress(), o.getLandmark(), o.getLat(), o.getLng(),
                        o.getRegion() == null ? null : o.getRegion().getName(), o.getOwner(),
                        o.getPriceType() == null ? PriceKind.WHOLESALE.name() : o.getPriceType().getCode().name(),
                        o.getStatus().name()))
                .toList();
    }

    /** Последний не отменённый заказ каждого магазина компании. */
    private List<LastOrderDto> lastOrders(Long companyId) {
        Map<Long, LastOrderDto> byOutlet = new LinkedHashMap<>();
        jdbc.query("""
                with last as (
                    select distinct on (o.outlet_id) o.id, o.outlet_id, o.created_at
                    from orders o
                    where o.company_id = ? and o.status not in ('CANCELLED', 'REFUSED')
                    order by o.outlet_id, o.created_at desc, o.id desc)
                select l.outlet_id, l.created_at, i.product_id, i.qty
                from last l join order_items i on i.order_id = l.id
                order by l.outlet_id, i.id""", rs -> {
            long outlet = rs.getLong("outlet_id");
            LastOrderDto last = byOutlet.get(outlet);
            if (last == null) {
                last = new LastOrderDto(outlet, rs.getTimestamp("created_at").toLocalDateTime().toLocalDate(), new ArrayList<>());
                byOutlet.put(outlet, last);
            }
            last.items().add(new ItemDto(rs.getLong("product_id"), rs.getInt("qty")));
        }, companyId);
        return List.copyOf(byOutlet.values());
    }
}
