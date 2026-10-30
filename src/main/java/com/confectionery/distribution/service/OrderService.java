package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.OrderRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orders;
    private final DebtService debts;
    private final Clock clock;

    /** Ещё не отгруженные: новые, собранные и ждущие разрешения — за любой день, старые первыми. */
    public List<Order> waiting() {
        return orders.findByStatusIn(EnumSet.of(OrderStatus.ACCEPTED, OrderStatus.ASSEMBLED, OrderStatus.NEEDS_APPROVAL)).stream()
                .sorted(Comparator.comparing(Order::getCreatedAt).thenComparing(Order::getId))
                .toList();
    }

    public Order get(Long id) {
        Order o = orders.findById(id).orElseThrow(NotFoundException::new);
        debts.fill(o.getOutlet());
        return o;
    }

    /** Лист сборки: все новые и собранные, ещё не отгруженные, по районам. */
    public List<Order> toPick() {
        return orders.findByStatusIn(EnumSet.of(OrderStatus.ACCEPTED, OrderStatus.ASSEMBLED)).stream()
                .sorted(Comparator.comparing((Order o) -> o.getOutlet().getRegion() == null ? "" : o.getOutlet().getRegion().getName())
                        .thenComparing(o -> o.getOutlet().getName()))
                .toList();
    }

    /** Лист сборки: товар → штук по всем заказам (рейса или на дату). */
    public record PickRow(Product product, int qty, int boxes, int pieces) {
    }

    public static List<PickRow> pickList(List<Order> list) {
        Map<Product, Integer> m = new LinkedHashMap<>();
        for (Order o : list) for (OrderLine l : o.getLines()) m.merge(l.getProduct(), l.getQty(), Integer::sum);
        return m.entrySet().stream()
                .sorted(Comparator.comparing(e -> e.getKey().getName()))
                .map(e -> {
                    int per = Math.max(1, e.getKey().getPerBox());
                    return new PickRow(e.getKey(), e.getValue(), e.getValue() / per, e.getValue() % per);
                }).toList();
    }

    /** Строка общей накладной: товар, штук, коробок + штук, сумма. */
    public record SumRow(Product product, int qty, int boxes, int pieces, long sum) {
    }

    /** Группа товаров в общей накладной: строки по названию и итог группы. */
    public record SumGroup(String name, List<SumRow> rows, int qty, int boxes, int pieces, long sum) {
    }

    /** Раздел общей накладной: группы и итог раздела. */
    public record Section(List<SumGroup> groups, int qty, int boxes, int pieces, long sum) {
        public boolean isEmpty() {
            return groups.isEmpty();
        }
    }

    /**
     * Общая накладная: отгружено; чистый возврат — что магазин не принял (закрыт, отказ, взял часть) и вернулось
     * целым; испорченный возврат — негодный товар, забранный у магазинов. Пока заказ не выдан, в испорченном
     * стоит то, что записал торговый (planned — сколько таких штук).
     */
    public record Waybill(Section shipped, Section clean, Section spoiled, int planned) {
    }

    public static Waybill waybill(List<Order> list) {
        Map<Product, long[]> shipped = new HashMap<>(), clean = new HashMap<>(), spoiled = new HashMap<>();
        Set<Order> set = new HashSet<>(list);
        Set<Outlet> outlets = new HashSet<>();
        Set<Trip> trips = new LinkedHashSet<>();
        int planned = 0;
        for (Order o : list) {
            outlets.add(o.getOutlet());
            if (o.getTrip() != null) trips.add(o.getTrip());
            for (OrderLine l : o.getLines()) {
                add(shipped, l.getProduct(), l.getQty(), l.getSum());
                Integer given = o.getStatus() == OrderStatus.REFUSED ? Integer.valueOf(0) : l.getDelivered();
                if (given != null && given < l.getQty()) add(clean, l.getProduct(), l.getQty() - given, (l.getQty() - given) * l.getNetPrice());
            }
            if (o.getDelivery() == null)
                for (OrderReturnLine r : o.getReturnLines()) {
                    add(spoiled, r.getProduct(), r.getQty(), r.getSum());
                    planned += r.getQty();
                }
        }
        // забранное экспедитором: по заказам из списка и без заказа — у тех же магазинов в тех же рейсах
        for (Trip t : trips)
            for (ProductReturn r : t.getReturns())
                if (r.getOrder() != null ? set.contains(r.getOrder()) : outlets.contains(r.getOutlet()))
                    for (ReturnLine l : r.getLines()) add(spoiled, l.getProduct(), l.getQty(), l.getSum());
        return new Waybill(section(shipped), section(clean), section(spoiled), planned);
    }

    private static void add(Map<Product, long[]> m, Product p, long qty, long sum) {
        long[] r = m.computeIfAbsent(p, k -> new long[2]);
        r[0] += qty;
        r[1] += sum;
    }

    /** Группы — по алфавиту, «без группы» в конце; товары в группе — по названию. */
    private static Section section(Map<Product, long[]> m) {
        Map<String, List<SumRow>> byGroup = new TreeMap<>(Comparator.comparing((String g) -> g.isEmpty()).thenComparing(Comparator.naturalOrder()));
        m.entrySet().stream()
                .sorted(Comparator.comparing(e -> e.getKey().getName()))
                .forEach(e -> {
                    int qty = (int) e.getValue()[0], per = Math.max(1, e.getKey().getPerBox());
                    String g = e.getKey().getCategory() == null ? "" : e.getKey().getCategory().strip();
                    byGroup.computeIfAbsent(g, k -> new ArrayList<>()).add(new SumRow(e.getKey(), qty, qty / per, qty % per, e.getValue()[1]));
                });
        List<SumGroup> groups = new ArrayList<>();
        byGroup.forEach((g, rows) -> groups.add(new SumGroup(g.isEmpty() ? "Без группы" : g, rows,
                rows.stream().mapToInt(SumRow::qty).sum(), rows.stream().mapToInt(SumRow::boxes).sum(),
                rows.stream().mapToInt(SumRow::pieces).sum(), rows.stream().mapToLong(SumRow::sum).sum())));
        return new Section(groups, groups.stream().mapToInt(SumGroup::qty).sum(), groups.stream().mapToInt(SumGroup::boxes).sum(),
                groups.stream().mapToInt(SumGroup::pieces).sum(), groups.stream().mapToLong(SumGroup::sum).sum());
    }

    /** Заказы для накладных: только видимые (своей компании), по рейсам, районам и магазинам. */
    public List<Order> forInvoices(Collection<Long> ids) {
        if (ids == null || ids.isEmpty()) return List.of();
        return orders.findAllById(ids).stream()
                .sorted(Comparator.comparing((Order o) -> o.getTrip() == null ? "" : o.getTrip().getNumber())
                        .thenComparing(o -> o.getOutlet().getRegion() == null ? "" : o.getOutlet().getRegion().getName())
                        .thenComparing(o -> o.getOutlet().getName()))
                .toList();
    }


    /** «Собран»: отмеченные новые заказы собраны на складе. Возвращает, сколько отмечено; остальные не меняются. */
    @Transactional
    public int assemble(Collection<Long> ids, Actor actor) {
        if (ids == null || ids.isEmpty()) throw new FormException("Отметьте галочками заказы, которые собраны");
        LocalDateTime now = LocalDateTime.now(clock);
        int n = 0;
        for (Order o : orders.lockAll(ids)) {
            if (o.getStatus() != OrderStatus.ACCEPTED) continue;
            o.setStatus(OrderStatus.ASSEMBLED);
            o.event(now, actor.entity(), actor.who(), "Собран");
            n++;
        }
        return n;
    }

    @Transactional
    public Order cancel(Long id, Actor actor, String reason) {
        Order o = orders.findById(id).orElseThrow(NotFoundException::new);
        if (o.getStatus().cancellable()) {
            o.setStatus(OrderStatus.CANCELLED);
            o.event(LocalDateTime.now(clock), actor.entity(), actor.who(), "Отменил: " + reason);
        }
        return o;
    }
}
