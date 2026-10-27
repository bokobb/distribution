package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.repository.OrderRepository;
import com.confectionery.distribution.repository.TripOrderRepository;
import com.confectionery.distribution.repository.TripRepository;
import com.confectionery.distribution.repository.VehicleRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class TripService {

    private static final DateTimeFormatter NUMBER_DATE = DateTimeFormatter.ofPattern("ddMMyy");

    private final TripRepository trips;
    private final TripOrderRepository tripOrders;
    private final OrderRepository orders;
    private final EmployeeRepository employees;
    private final VehicleRepository vehicles;
    private final StockService stock;
    private final Clock clock;

    /** Рейсы сегодня и незакрытые прошлых дней (касса ещё у экспедитора); companyId = null — все видимые. */
    public List<Trip> current(Long companyId) {
        return trips.findByDateOrStatusIn(LocalDate.now(clock), EnumSet.of(TripStatus.ON_ROAD, TripStatus.RETURNED)).stream()
                .filter(t -> companyId == null || companyId.equals(t.getCompanyId()))
                .sorted(Comparator.comparing((Trip t) -> t.getStatus().ordinal()).thenComparing(Trip::getNumber))
                .toList();
    }

    /** Для страницы «Рейсы»: текущие и загружаемые на следующие дни. */
    public List<Trip> forPage(Long companyId) {
        List<Trip> out = new ArrayList<>(current(companyId));
        trips.findByStatusAndDateAfter(TripStatus.LOADING, LocalDate.now(clock)).stream()
                .filter(t -> companyId == null || companyId.equals(t.getCompanyId()))
                .sorted(Comparator.comparing(Trip::getDate).thenComparing(Trip::getNumber))
                .forEach(out::add);
        return out;
    }

    public Trip get(Long id) {
        return trips.findById(id).orElseThrow(NotFoundException::new);
    }

    /** Итог отгрузки: рейсы, сколько заказов ушло, какие не ушли и почему (причина → номера заказов). */
    public record Shipment(Employee expeditor, List<Trip> trips, int shipped, Map<String, List<String>> skipped) {
    }

    /**
     * Отгрузить заказы экспедитору: каждый день доставки — в его рейс на этот день (рейс, который ещё
     * загружается, дополняется, иначе создаётся новый), товар — с основного склада в машину, заказы — «В
     * рейсе». Уходят только принятые и собранные; остальные остаются как были и попадают в skipped. Если
     * на основном складе чего-то не хватает, не отгружается ничего.
     */
    @Transactional
    public Shipment ship(Collection<Long> orderIds, Long expeditorId, Actor actor) {
        if (orderIds == null || orderIds.isEmpty()) throw new FormException("Отметьте галочками заказы, которые нужно отгрузить");
        Employee exp = expeditorId == null ? null
                : employees.findById(expeditorId).filter(e -> e.getRole() == Role.EXPEDITOR).orElse(null);
        if (exp == null) throw new FormException("Выберите экспедитора");
        if (!exp.isActive()) throw new FormException("Экспедитор «" + exp.getName() + "» отключён");
        Vehicle car = vehicles.findAllByOrderByPlateAsc().stream()
                .filter(v -> v.isActive() && v.getExpeditor() != null && v.getExpeditor().getId().equals(exp.getId()))
                .findFirst().orElseThrow(() -> new FormException("За экспедитором «" + exp.getName()
                        + "» не закреплена машина — закрепите её в разделе «Сотрудники и машины»"));

        Map<String, List<String>> skipped = new LinkedHashMap<>();
        List<Order> ok = new ArrayList<>();
        for (Order o : orders.lockAll(orderIds)) {
            String why = !o.getCompanyId().equals(exp.getCompanyId()) ? "заказы другой компании"
                    : switch (o.getStatus()) {
                case ACCEPTED, ASSEMBLED -> null;
                case NEEDS_APPROVAL -> "ждут разрешения (долг сверх лимита)";
                case IN_TRIP -> "уже в рейсе";
                case CANCELLED -> "отменены";
                default -> "уже доставлены";
            };
            if (why == null) ok.add(o);
            else skipped.computeIfAbsent(why, k -> new ArrayList<>()).add(o.getNumber());
        }
        if (ok.isEmpty()) return new Shipment(exp, List.of(), 0, skipped);

        // сначала проверка всего товара разом: отгрузка не должна остановиться на середине
        Warehouse main = stock.warehouse(exp.getCompany(), WarehouseType.MAIN);
        Map<Product, Integer> need = new TreeMap<>(Comparator.comparing(Product::getName).thenComparing(Product::getId));
        for (Order o : ok) for (OrderLine l : o.getLines()) need.merge(l.getProduct(), l.getQty(), Integer::sum);
        List<String> lack = new ArrayList<>();
        need.forEach((p, q) -> {
            int have = stock.qty(main, p);
            if (have < q) lack.add("«" + p.getName() + "» — есть " + have + ", нужно " + q);
        });
        if (!lack.isEmpty())
            throw new FormException("Не хватает товара на основном складе, ничего не отгружено: " + String.join("; ", lack));

        LocalDate today = LocalDate.now(clock);
        LocalDateTime now = LocalDateTime.now(clock);
        Map<LocalDate, List<Order>> byDay = ok.stream().collect(Collectors.groupingBy(
                o -> o.getDeliveryDate().isBefore(today) ? today : o.getDeliveryDate(), TreeMap::new, Collectors.toList()));
        List<Trip> used = new ArrayList<>();
        byDay.forEach((day, list) -> {
            Trip t = trips.findFirstByExpeditorAndDateAndStatusOrderByIdDesc(exp, day, TripStatus.LOADING)
                    .orElseGet(() -> newTrip(exp, car, day));
            Warehouse carStock = stock.warehouse(t.getVehicle());
            int pos = t.getTripOrders().stream().mapToInt(TripOrder::getPosition).max().orElse(-1) + 1;
            list.sort(Comparator.comparing((Order o) -> o.getOutlet().getRoute() == null ? "" : o.getOutlet().getRoute().getName())
                    .thenComparing(o -> o.getOutlet().getName()));
            for (Order o : list) {
                TripOrder to = new TripOrder().setTrip(t).setOrder(o).setPosition(pos++);
                to.setCompany(o.getCompany());
                tripOrders.save(to);
                for (OrderLine l : o.getLines())
                    stock.move(l.getProduct(), l.getQty(), main, carStock, MovementReason.LOAD, actor, now, m -> m.setTrip(t).setOrder(o));
                o.setStatus(OrderStatus.IN_TRIP);
                o.event(now, actor.entity(), actor.who(), "Отгрузил экспедитору " + exp.getName() + ", рейс " + t.getNumber());
            }
            used.add(t);
        });
        return new Shipment(exp, used, ok.size(), skipped);
    }

    private Trip newTrip(Employee exp, Vehicle car, LocalDate day) {
        String base = "Р-" + day.format(NUMBER_DATE) + "-";
        int n = 1;
        while (trips.existsByCompanyIdAndNumber(exp.getCompanyId(), base + n)) n++;
        Trip t = new Trip().setNumber(base + n).setDate(day).setExpeditor(exp).setVehicle(car).setStatus(TripStatus.LOADING);
        t.setCompany(exp.getCompany());
        return trips.save(t);
    }
}
