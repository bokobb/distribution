package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.*;
import java.util.function.Consumer;

/** Склад: остатки, приходы, движения товара. Остаток меняется только вместе с движением. */
@Service
@RequiredArgsConstructor
public class StockService {

    private static final Set<OrderStatus> RESERVED = EnumSet.of(OrderStatus.ACCEPTED, OrderStatus.NEEDS_APPROVAL, OrderStatus.ASSEMBLED);

    private final StockBalanceRepository balances;
    private final StockMovementRepository movements;
    private final WarehouseRepository warehouses;
    private final ReceiptRepository receipts;
    private final OrderRepository orders;
    private final CatalogService catalog;
    private final Clock clock;

    /** Строка склада: товар, основной склад, в машинах, в резерве под заказы на завтра, негодный. */
    public record StockRow(Product product, int main, int inVehicles, int reserved, int defect) {
        public int free() {
            return main - reserved;
        }

        public boolean low() {
            return free() < product.getPerBox() * 2;
        }
    }

    public List<StockRow> rows(Long companyId) {
        List<Product> list = catalog.products(companyId);
        Map<Product, int[]> m = new LinkedHashMap<>();
        for (Product p : list) m.put(p, new int[4]);
        for (StockBalance b : balances.findAll()) {
            int[] r = m.get(b.getProduct());
            if (r == null) continue;
            switch (b.getWarehouse().getType()) {
                case MAIN -> r[0] += b.getQty();
                case VEHICLE -> r[1] += b.getQty();
                case DEFECT -> r[3] += b.getQty();
            }
        }
        for (Order o : orders.findByStatusIn(RESERVED)) {
            for (OrderLine l : o.getLines()) {
                int[] r = m.get(l.getProduct());
                if (r != null) r[2] += l.getQty();
            }
        }
        List<StockRow> out = new ArrayList<>();
        m.forEach((p, r) -> out.add(new StockRow(p, r[0], r[1], r[2], r[3])));
        return out;
    }

    public Warehouse warehouse(Company c, WarehouseType type) {
        return warehouses.findByCompanyIdAndType(c.getId(), type).orElseThrow(
                () -> new IllegalStateException("У компании «" + c.getName() + "» нет склада: " + type.getLabel()));
    }

    public Warehouse warehouse(Vehicle v) {
        return warehouses.findByVehicle(v).orElseThrow(() -> new IllegalStateException("У машины " + v.getPlate() + " нет склада"));
    }

    /**
     * Переместить товар: from — списать (нельзя уйти в минус), to — добавить. Пустой from — товар
     * пришёл извне, пустой to — ушёл в магазин. refs заполняет документ движения (рейс, заказ…).
     */
    @Transactional
    public StockMovement move(Product p, int qty, Warehouse from, Warehouse to, MovementReason reason,
                              Actor actor, LocalDateTime at, Consumer<StockMovement> refs) {
        if (qty <= 0) throw new IllegalArgumentException("Количество должно быть больше нуля");
        if (from != null) {
            StockBalance b = balance(from, p);
            if (b.getQty() < qty)
                throw new IllegalStateException("Не хватает «" + p.getName() + "» на складе «" + from.getName() + "»: есть " + b.getQty() + ", нужно " + qty);
            b.setQty(b.getQty() - qty);
        }
        if (to != null) {
            StockBalance b = balance(to, p);
            b.setQty(b.getQty() + qty);
        }
        StockMovement m = new StockMovement().setMovedAt(at != null ? at : LocalDateTime.now(clock)).setProduct(p).setQty(qty)
                .setFrom(from).setTo(to).setReason(reason).setUser(actor == null ? null : actor.entity());
        m.setCompany(p.getCompany());
        if (refs != null) refs.accept(m);
        return movements.save(m);
    }

    private StockBalance balance(Warehouse w, Product p) {
        return balances.findByWarehouseAndProduct(w, p).orElseGet(() -> {
            StockBalance b = new StockBalance().setWarehouse(w).setProduct(p);
            b.setCompany(w.getCompany());
            return balances.save(b);
        });
    }

    // ------------------------------------------------------------------ приходы

    public List<Receipt> receipts() {
        return receipts.findAllByOrderByDateDescIdDesc();
    }

    public Receipt receipt(Long id) {
        return receipts.findById(id).orElseThrow(NotFoundException::new);
    }

    /** Принять приход: фактические количества (не указано — как в документе) уходят на склад. */
    @Transactional
    public void confirmReceipt(Long id, Map<Long, Integer> actual, Actor actor) {
        Receipt r = receipt(id);
        if (r.getStatus() != ReceiptStatus.DRAFT) return;
        LocalDateTime now = LocalDateTime.now(clock);
        for (ReceiptLine l : r.getLines()) {
            int q = actual.getOrDefault(l.getProduct().getId(), l.getExpected());
            l.setActual(q);
            if (q > 0) move(l.getProduct(), q, null, r.getWarehouse(), MovementReason.RECEIPT, actor, now, m -> m.setReceipt(r));
        }
        r.setStatus(ReceiptStatus.CONFIRMED).setConfirmedByUser(actor == null ? null : actor.entity()).setConfirmedAt(now);
    }
}
