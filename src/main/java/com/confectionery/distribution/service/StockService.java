package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
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
    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** Строка склада: товар, основной склад, в машинах, в резерве под неотгруженные заказы, негодный. */
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

    /**
     * Свободно для заказа: основной склад минус неотгруженные заказы (те же статусы, что RESERVED), кроме
     * exceptOrderId — у правки заказа его товар свой. Товар → штук; меньше нуля, если склад ушёл в минус.
     */
    public Map<Long, Integer> free(Long companyId, Long exceptOrderId) {
        Map<Long, Integer> out = new HashMap<>();
        jdbc.query("""
                select p.id, coalesce(b.qty, 0) - coalesce(r.qty, 0)
                from products p
                left join warehouses w on w.company_id = p.company_id and w.type = 'MAIN'
                left join stock_balances b on b.warehouse_id = w.id and b.product_id = p.id
                left join (select i.product_id, sum(i.qty) qty from order_items i join orders o on o.id = i.order_id
                           where o.company_id = ? and o.status in ('ACCEPTED', 'NEEDS_APPROVAL', 'ASSEMBLED') and o.id <> ?
                           group by i.product_id) r on r.product_id = p.id
                where p.company_id = ?""",
                rs -> {
                    out.put(rs.getLong(1), rs.getInt(2));
                }, companyId, exceptOrderId == null ? -1L : exceptOrderId, companyId);
        return out;
    }

    /** Чего заказу не хватает на складе: товар → {заказано, свободно}; всё есть — пусто. */
    public Map<Product, int[]> shortage(Order o) {
        Map<Long, Integer> free = free(o.getCompanyId(), o.getId());
        Map<Product, int[]> out = new LinkedHashMap<>();
        for (OrderLine l : o.getLines()) {
            int f = free.getOrDefault(l.getProduct().getId(), 0);
            if (l.getQty() > f) out.put(l.getProduct(), new int[]{l.getQty(), Math.max(0, f)});
        }
        return out;
    }

    /**
     * Ввод остатков (первый раз или после пересчёта): на основном складе становится столько, сколько указано;
     * разница — движение «ввод остатков». Не указано — товар не трогается. Возвращает, у скольких товаров изменилось.
     */
    @Transactional
    public int count(Company c, Map<Long, Integer> actual, Actor actor) {
        Warehouse main = warehouse(c, WarehouseType.MAIN);
        LocalDateTime now = LocalDateTime.now(clock);
        int changed = 0;
        for (Product p : catalog.products(c.getId())) {
            Integer want = actual.get(p.getId());
            if (want == null) continue;
            int have = qty(main, p);
            if (want == have) continue;
            if (want > have) move(p, want - have, null, main, MovementReason.ADJUST, actor, now, null);
            else move(p, have - want, main, null, MovementReason.ADJUST, actor, now, null);
            changed++;
        }
        return changed;
    }

    /** «Булочки» — заказано 30, свободно 12; … */
    public static String shortageText(Map<Product, int[]> m) {
        StringJoiner j = new StringJoiner("; ");
        m.forEach((p, q) -> j.add("«" + p.getName() + "» — заказано " + q[0] + ", свободно " + q[1]));
        return j.toString();
    }

    public Warehouse warehouse(Company c, WarehouseType type) {
        return warehouses.findByCompanyIdAndType(c.getId(), type).orElseThrow(
                () -> new IllegalStateException("У компании «" + c.getName() + "» нет склада: " + type.getLabel()));
    }

    public Warehouse warehouse(Vehicle v) {
        return warehouses.findByVehicle(v).orElseThrow(() -> new IllegalStateException("У машины " + v.getPlate() + " нет склада"));
    }

    /**
     * Переместить товар: from — списать (в минус нельзя; только загрузка машины с основного склада —
     * отгрузка не ждёт прихода, минус закроет приход из CRM), to — добавить. Пустой from — товар
     * пришёл извне, пустой to — ушёл в магазин. refs заполняет документ движения (рейс, заказ…).
     */
    @Transactional
    public StockMovement move(Product p, int qty, Warehouse from, Warehouse to, MovementReason reason,
                              Actor actor, LocalDateTime at, Consumer<StockMovement> refs) {
        if (qty <= 0) throw new IllegalArgumentException("Количество должно быть больше нуля");
        if (from != null) {
            StockBalance b = balance(from, p);
            boolean minus = reason == MovementReason.LOAD && from.getType() == WarehouseType.MAIN;
            if (!minus && b.getQty() < qty)
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

    /** Остаток товара на складе (строка остатка блокируется до конца транзакции). */
    public int qty(Warehouse w, Product p) {
        return balances.findByWarehouseAndProduct(w, p).map(StockBalance::getQty).orElse(0);
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
