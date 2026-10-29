package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.ProductRepository;
import com.confectionery.distribution.repository.TripRepository;
import com.confectionery.distribution.service.AgentDataService.OutletDto;
import com.confectionery.distribution.service.AgentDataService.ProductDto;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;

/**
 * Всё, что нужно экспедитору на телефоне для работы без сети: его незакрытые рейсы по сегодня и отгруженные на
 * завтра (посмотреть заранее), точки по порядку — магазин с долгом и заказ с составом, ценами, оплатой и тем, что
 * уже выдано и оплачено; товары с ценами на сегодня (для возврата негодного — по цене продажи магазину в этот
 * день); название компании для накладной. Компания — из входа (TenantContext).
 */
@Service
@RequiredArgsConstructor
public class ExpeditorDataService {

    private static final Set<TripStatus> OPEN = EnumSet.of(TripStatus.LOADING, TripStatus.ON_ROAD, TripStatus.RETURNED);

    private final TripRepository trips;
    private final ProductRepository products;
    private final CatalogService catalog;
    private final DebtService debts;
    private final SettingsService settings;
    private final Clock clock;

    /** Что экспедитор может принять: Kaspi, отдать в долг; интервал GPS рабочего дня. */
    /** workStart, workEnd — рабочее время «08:00»: открыл приложение в это время — день начинается сам. */
    public record Settings(boolean acceptKaspi, boolean allowCredit, int gpsInterval, String workStart, String workEnd) {
    }

    /** price — за штуку с учётом скидки строки; delivered — сколько выдано, null — ещё не выдавали. */
    public record LineDto(Long productId, String name, String unit, int perBox, int qty, long price, Integer delivered) {
    }

    /** Что магазин отдаёт назад — записал торговый с заказом; reason — EXPIRED, DEFECT или PACKAGING. */
    public record ReturnLineDto(Long productId, String name, int qty, long price, String reason) {
    }

    /** payment — CASH, KASPI, CREDIT, как оформил агент; paid — сколько уже оплачено по заказу; returns — возврат,
     * который торговый записал с заказом: экспедитор забирает его при доставке. */
    public record OrderDto(Long id, UUID uuid, String number, String agent, LocalDate deliveryDate, String payment,
                           String comment, String status, String statusLabel, long total, long paid, List<LineDto> lines,
                           List<ReturnLineDto> returns) {
    }

    public record StopDto(int position, OutletDto outlet, OrderDto order) {
    }

    /**
     * Деньги и возвраты рейса, как их увидит касса: наличные и Kaspi — все оплаты рейса (за заказы и в счёт долгов),
     * oldDebt — из них оплаты долгов; возвраты негодного — штук и на сколько уменьшили долги.
     */
    public record CashDto(long cash, long kaspi, long oldDebt, int returnsQty, long returnsTotal) {
    }

    public record TripDto(Long id, String number, LocalDate date, String status, String statusLabel, String vehicle,
                          List<StopDto> stops, CashDto cash) {
    }

    public record CompanyDto(String name, String phone) {
    }

    public record ExpeditorData(LocalDate date, LocalDateTime syncedAt, CompanyDto company, Settings settings,
                                List<ProductDto> products, List<TripDto> trips) {
    }

    @Transactional(readOnly = true)
    public ExpeditorData of(Long expeditorId, Long companyId) {
        LocalDate today = LocalDate.now(clock);
        List<Trip> mine = trips.findByExpeditorIdAndStatusInOrderByDateAscNumberAsc(expeditorId, OPEN).stream()
                .filter(t -> !t.getDate().isAfter(today.plusDays(1))).toList();
        Set<Outlet> outlets = new LinkedHashSet<>();
        mine.forEach(t -> t.getOrders().forEach(o -> outlets.add(o.getOutlet())));
        debts.fill(outlets);

        List<Product> active = products.findAllByOrderByNameAsc().stream().filter(Product::isActive).toList();
        catalog.fillPrices(active);
        CompanySettings s = settings.of(companyId);
        Company company = mine.isEmpty() ? null : mine.get(0).getCompany();

        return new ExpeditorData(today, LocalDateTime.now(clock).truncatedTo(ChronoUnit.SECONDS),
                company == null ? null : new CompanyDto(company.getName(), company.getPhone()),
                new Settings(s.isAcceptKaspi(), s.isAllowCredit(), s.getGpsInterval(), s.getWorkStart().toString(),
                        s.getWorkEnd().toString()),
                active.stream().map(p -> new ProductDto(p.getId(), p.getName(), p.getCategory(), p.getUnit(), p.getPerBox(),
                        p.getBarcode(), p.getWholesale(), p.getRetail())).toList(),
                mine.stream().map(ExpeditorDataService::trip).toList());
    }

    private static TripDto trip(Trip t) {
        Map<Long, Long> paid = new HashMap<>();
        t.getPayments().stream().filter(p -> p.getOrder() != null)
                .forEach(p -> paid.merge(p.getOrder().getId(), p.getAmount(), Long::sum));
        List<StopDto> stops = new ArrayList<>();
        for (TripOrder to : t.getTripOrders()) {
            Order o = to.getOrder();
            if (o.getStatus() == OrderStatus.CANCELLED) continue;
            List<LineDto> lines = o.getLines().stream()
                    .map(l -> new LineDto(l.getProduct().getId(), l.getProduct().getName(), l.getProduct().getUnit(),
                            l.getProduct().getPerBox(), l.getQty(), l.getNetPrice(), l.getDelivered()))
                    .toList();
            stops.add(new StopDto(to.getPosition(), AgentDataService.outlet(o.getOutlet()),
                    new OrderDto(o.getId(), o.getUuid(), o.getNumber(), o.getAgent() == null ? null : o.getAgent().getName(),
                            o.getDeliveryDate(), o.getPayment().name(), o.getComment(), o.getStatus().name(), o.getStatus().getLabel(),
                            o.getTotal(), paid.getOrDefault(o.getId(), 0L), lines,
                            o.getReturnLines().stream().map(l -> new ReturnLineDto(l.getProduct().getId(),
                                    l.getProduct().getName(), l.getQty(), l.getPrice(), l.getReason().name())).toList())));
        }
        return new TripDto(t.getId(), t.getNumber(), t.getDate(), t.getStatus().name(), t.getStatus().getLabel(),
                t.getVehicle() == null ? null : t.getVehicle().getPlate(), stops,
                new CashDto(t.getCash(), t.getKaspi(), t.getOldDebtCollected(), t.getReturnsQty(), t.getReturnsTotal()));
    }
}
