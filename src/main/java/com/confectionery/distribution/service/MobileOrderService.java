package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.repository.OrderRepository;
import com.confectionery.distribution.repository.OutletRepository;
import com.confectionery.distribution.repository.ProductRepository;
import com.confectionery.distribution.repository.VisitRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * Заказ торгового агента с телефона. Телефон собирает заказ без сети и шлёт его, когда есть связь; uuid
 * создаёт телефон, поэтому повтор возвращает уже принятый заказ. Цены сервер берёт сам — по прайсу магазина
 * на день заказа, а не с телефона. В долг сверх лимита магазина — «Нужно разрешение», если так в настройках.
 * Вместе с заказом торговый может записать возврат негодного товара: экспедитор заберёт его при доставке, к оплате
 * будет заказ минус возврат; долг уменьшится, когда экспедитор запишет, сколько забрал на самом деле.
 * Пока заказ не отгружен экспедитору («Принят», «Нужно разрешение»), торговый может его изменить или отменить.
 */
@Service
@RequiredArgsConstructor
public class MobileOrderService {

    /** Время на телефоне может спешить — дальше этого запаса в будущее заказ не принимается. */
    private static final int CLOCK_SKEW_MIN = 10;
    /** Доставка — не дальше стольких дней от заказа. */
    static final int MAX_DELIVERY_DAYS = 14;
    private static final int MAX_QTY = 100_000;
    private static final DateTimeFormatter NUMBER_DATE = DateTimeFormatter.ofPattern("ddMMyy");
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd.MM");

    private final OrderRepository orders;
    private final EmployeeRepository employees;
    private final OutletRepository outlets;
    private final ProductRepository products;
    private final VisitRepository visits;
    private final CatalogService catalog;
    private final DebtService debts;
    private final SettingsService settings;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    public record ItemIn(Long productId, Integer qty) {
    }

    /** reason — не обязательна (старые телефоны: EXPIRED, DEFECT или PACKAGING). */
    public record ReturnItemIn(Long productId, Integer qty, String reason) {
    }

    /** payment — CASH, KASPI или CREDIT; deliveryDate не задана — через сколько дней по настройкам компании; returns — что
     * экспедитор заберёт у магазина при доставке (может не быть). */
    public record OrderIn(UUID uuid, UUID visitUuid, Long outletId, LocalDateTime createdAt, LocalDate deliveryDate,
                          String payment, String comment, List<ItemIn> items, List<ReturnItemIn> returns) {
    }

    public record LineOut(Long productId, String name, int qty, long price, long sum) {
    }

    public record ReturnLineOut(Long productId, String name, int qty, long price, long sum, String reason) {
    }

    /** Правка заказа: всё целиком, как при отправке. */
    public record EditIn(LocalDate deliveryDate, String payment, String comment, List<ItemIn> items,
                         List<ReturnItemIn> returns) {
    }

    public record CancelIn(String reason) {
    }

    /** status — имя OrderStatus; note — для агента: почему ждёт разрешения, отменён или отказ; returnTotal — сколько
     * вычтется за возврат; deliveredAt — когда экспедитор отдал товар (последняя выдача), не отдал — null; comment —
     * чтобы торговый, меняя заказ, видел свой комментарий. */
    public record OrderOut(UUID uuid, Long outletId, String number, LocalDateTime createdAt, LocalDate deliveryDate,
                           String payment, String status, String statusLabel, String note, long total,
                           List<LineOut> lines, long returnTotal, List<ReturnLineOut> returns, LocalDateTime deliveredAt,
                           String comment) {
    }

    @Transactional
    public OrderOut save(Long agentId, OrderIn in) {
        if (in.uuid() == null || in.outletId() == null || in.items() == null || in.items().isEmpty())
            throw new FormException("Заказ без магазина или товаров — обновите приложение");
        Employee agent = employees.findById(agentId).orElseThrow(NotFoundException::new);
        // номер заказа по порядку и защита от одновременного повтора — по очереди внутри компании
        jdbc.queryForList("select pg_advisory_xact_lock(hashtext('distribution-order'), ?)", agent.getCompanyId().intValue());
        Order was = orders.findByUuid(in.uuid()).orElse(null);
        if (was != null) {
            if (was.getAgent() == null || !was.getAgent().getId().equals(agentId))
                throw new FormException("Этот заказ записан другим сотрудником");
            return out(was);
        }

        LocalDateTime now = LocalDateTime.now(clock);
        LocalDateTime at = in.createdAt() == null ? now : in.createdAt();
        if (at.isAfter(now.plusMinutes(CLOCK_SKEW_MIN)))
            throw new FormException("Время заказа неверное — проверьте дату и время на телефоне");
        CompanySettings st = settings.of(agent.getCompanyId());
        Outlet outlet = outlets.findById(in.outletId())
                .orElseThrow(() -> new FormException("Магазин не найден — обновите данные на телефоне"));
        if (outlet.getStatus() == OutletStatus.CLOSED) throw new FormException("Магазин закрыт — заказ не принят");
        Order o = new Order().setUuid(in.uuid()).setOutlet(outlet).setAgent(agent).setCreatedAt(at)
                .setNumber(number(agent.getCompanyId(), at.toLocalDate()));
        o.setCompany(agent.getCompany());
        terms(o, in.payment(), in.deliveryDate(), in.comment(), st, null);
        if (in.visitUuid() != null)
            visits.findByUuid(in.visitUuid()).filter(v -> v.getAgent().getId().equals(agentId)).ifPresent(o::setVisit);
        fill(o, in.items(), in.returns());

        o.setStatus(OrderStatus.ACCEPTED);
        o.event(now, agent, who(agent), "Принят с телефона");
        limit(o, st, now);
        return out(orders.save(o));
    }

    /**
     * Правка заказа торговым, пока его не отгрузили: товары, возврат, оплата, день доставки, комментарий — целиком,
     * как при отправке. Цены — по прайсу на день заказа, лимит долга проверяется заново (разрешение оператора — тоже
     * заново). В истории — что изменилось; ничего не изменилось — заказ как был.
     */
    @Transactional
    public OrderOut edit(Long agentId, UUID uuid, EditIn in) {
        Order o = mine(agentId, uuid);
        changeable(o);
        LocalDateTime now = LocalDateTime.now(clock);
        CompanySettings st = settings.of(o.getCompanyId());
        OrderStatus wasStatus = o.getStatus();
        PaymentMethod wasPayment = o.getPayment();
        LocalDate wasDelivery = o.getDeliveryDate();
        String wasComment = o.getComment(), wasLines = lines(o), wasReturns = returns(o);
        int wasCount = o.getLines().size();
        long wasTotal = o.getTotal(), wasReturnTotal = o.getReturnTotal();

        terms(o, in.payment(), in.deliveryDate(), in.comment(), st, now.toLocalDate());
        fill(o, in.items(), in.returns());

        List<String> changes = new ArrayList<>();
        if (!wasLines.equals(lines(o)))
            changes.add("товары: было " + wasCount + " поз. на " + money(wasTotal) + ", стало " + o.getLines().size()
                    + " поз. на " + money(o.getTotal()));
        if (!wasReturns.equals(returns(o)))
            changes.add("возврат: было " + money(wasReturnTotal) + ", стало " + money(o.getReturnTotal()));
        if (wasPayment != o.getPayment())
            changes.add("оплата: " + wasPayment.getLabel() + " → " + o.getPayment().getLabel());
        if (!wasDelivery.equals(o.getDeliveryDate()))
            changes.add("доставка: " + wasDelivery.format(DAY) + " → " + o.getDeliveryDate().format(DAY));
        if (!Objects.equals(wasComment, o.getComment())) changes.add("новый комментарий");
        if (changes.isEmpty()) return out(o);

        o.event(now, o.getAgent(), who(o.getAgent()), "Изменён торговым — " + String.join("; ", changes));
        o.setStatus(OrderStatus.ACCEPTED);
        limit(o, st, now);
        if (wasStatus == OrderStatus.NEEDS_APPROVAL && o.getStatus() == OrderStatus.ACCEPTED)
            o.event(now, null, "Система", "В пределах лимита — разрешение не нужно");
        return out(o);
    }

    /** Отмена заказа торговым, пока его не отгрузили: заказ остаётся в истории «Отменён» с причиной. Повтор — как был. */
    @Transactional
    public OrderOut cancel(Long agentId, UUID uuid, String reason) {
        Order o = mine(agentId, uuid);
        if (o.getStatus() == OrderStatus.CANCELLED) return out(o);
        changeable(o);
        String why = cut(reason, 200);
        if (why == null) throw new FormException("Укажите, почему отменяете заказ");
        o.setStatus(OrderStatus.CANCELLED);
        o.event(LocalDateTime.now(clock), o.getAgent(), who(o.getAgent()), "Отменён торговым: " + why);
        return out(o);
    }

    /** Свой заказ по uuid — под блокировкой: в это же время оператор может его отгружать. */
    private Order mine(Long agentId, UUID uuid) {
        Long id = orders.idByUuid(uuid)
                .orElseThrow(() -> new FormException("Заказ ещё не дошёл до сервера — попробуйте через минуту"));
        Order o = orders.lockAll(List.of(id)).get(0);
        if (o.getAgent() == null || !o.getAgent().getId().equals(agentId))
            throw new FormException("Это заказ другого сотрудника");
        return o;
    }

    /** Торговый меняет и отменяет заказ, пока его не отгрузили экспедитору. */
    private static void changeable(Order o) {
        if (o.getStatus() != OrderStatus.ACCEPTED && o.getStatus() != OrderStatus.NEEDS_APPROVAL)
            throw new FormException("Заказ " + o.getNumber() + " уже «" + o.getStatus().getLabel()
                    + "» — изменить или отменить его может только оператор");
    }

    /** Оплата, день доставки (с дня заказа, не дальше двух недель; при правке — не раньше notBefore) и комментарий. */
    private void terms(Order o, String payment, LocalDate deliveryDate, String comment, CompanySettings st,
                       LocalDate notBefore) {
        PaymentMethod p = payment(payment, st);
        if (p == PaymentMethod.CREDIT && o.getOutlet().getStatus() == OutletStatus.PENDING && st.isFirstOrderCash())
            throw new FormException("Магазин ещё на проверке — первый заказ без долга: наличные или Kaspi");
        LocalDate day = o.getCreatedAt().toLocalDate();
        LocalDate delivery = deliveryDate == null ? day.plusDays(st.getDeliveryDays()) : deliveryDate;
        if (delivery.isBefore(day) || delivery.isAfter(day.plusDays(MAX_DELIVERY_DAYS)))
            throw new FormException("Дата доставки — с дня заказа и не дальше " + MAX_DELIVERY_DAYS + " дней");
        if (notBefore != null && delivery.isBefore(notBefore))
            throw new FormException("День доставки уже прошёл — выберите сегодня или позже");
        o.setPayment(p).setDeliveryDate(delivery).setComment(cut(comment, 500));
    }

    /**
     * Товары и возврат по прайсу магазина на день заказа. Строки, которые уже есть, меняются на месте (товар в заказе
     * и в возврате — один раз): при правке не продаётся больше или пропала цена — остаются с прежней ценой.
     */
    private void fill(Order o, List<ItemIn> items, List<ReturnItemIn> returns) {
        if (items == null || items.isEmpty()) throw new FormException("В заказе нет товаров");
        Map<Long, Integer> qty = new LinkedHashMap<>();
        for (ItemIn i : items) {
            if (i.productId() == null || i.qty() == null || i.qty() <= 0 || i.qty() > MAX_QTY)
                throw new FormException("Неверное количество товара — проверьте заказ");
            qty.merge(i.productId(), i.qty(), Integer::sum);
        }
        Map<Long, Long> prices = catalog.pricesOn(o.getOutlet().getPriceType(), o.getCreatedAt().toLocalDate());
        Map<Long, OrderLine> had = new HashMap<>();
        o.getLines().forEach(l -> had.put(l.getProduct().getId(), l));
        o.getLines().removeIf(l -> !qty.containsKey(l.getProduct().getId()));
        for (Map.Entry<Long, Integer> e : qty.entrySet()) {
            OrderLine l = had.get(e.getKey());
            Product p = l != null ? l.getProduct() : products.findById(e.getKey()).filter(Product::isActive)
                    .orElseThrow(() -> new FormException("Товар больше не продаётся — обновите данные на телефоне"));
            Long price = prices.getOrDefault(p.getId(), l == null ? null : l.getPrice());
            if (price == null) throw new FormException("Нет цены на «" + p.getName() + "» — обратитесь к оператору");
            if (l == null) o.addLine(new OrderLine().setProduct(p).setQty(e.getValue()).setPrice(price));
            else l.setQty(e.getValue()).setPrice(price);
        }

        Map<Long, ReturnItemIn> back = new LinkedHashMap<>();
        for (ReturnItemIn r : returns == null ? List.<ReturnItemIn>of() : returns) {
            if (r.productId() == null || r.qty() == null || r.qty() <= 0 || r.qty() > MAX_QTY)
                throw new FormException("Неверное количество в возврате — проверьте возврат");
            if (back.put(r.productId(), r) != null) throw new FormException("Товар в возврате дважды — обновите приложение");
        }
        Map<Long, OrderReturnLine> hadBack = new HashMap<>();
        o.getReturnLines().forEach(l -> hadBack.put(l.getProduct().getId(), l));
        o.getReturnLines().removeIf(l -> !back.containsKey(l.getProduct().getId()));
        for (ReturnItemIn r : back.values()) {
            OrderReturnLine l = hadBack.get(r.productId());
            Product p = l != null ? l.getProduct() : products.findById(r.productId())
                    .orElseThrow(() -> new FormException("Товар не найден — обновите данные на телефоне"));
            Long price = prices.getOrDefault(p.getId(), l == null ? null : l.getPrice());
            if (price == null) throw new FormException("Нет цены на «" + p.getName() + "» — обратитесь к оператору");
            if (l == null)
                o.addReturnLine(new OrderReturnLine().setProduct(p).setQty(r.qty()).setPrice(price).setReason(reason(r.reason())));
            else l.setQty(r.qty()).setPrice(price).setReason(reason(r.reason()));
        }
    }

    /**
     * Магазин закрыт по просрочке — «Нужно разрешение» директора или владельца (любой заказ). В долг сверх лимита
     * магазина — «Нужно разрешение» оператора, если так в настройках, иначе только запись в истории.
     */
    private void limit(Order o, CompanySettings st, LocalDateTime now) {
        Outlet outlet = o.getOutlet();
        o.setHold(null);
        debts.fill(outlet);
        if (st.blocks(outlet)) {
            o.setStatus(OrderStatus.NEEDS_APPROVAL).setHold(ApprovalKind.OVERDUE);
            o.event(now, null, "Система", "Заказ закрыт: просрочка " + money(outlet.getOverdue()) + ", "
                    + outlet.getOverdueDays() + " дн. — нужно разрешение (" + st.unblockersText() + ")");
            return;
        }
        if (o.getPayment() != PaymentMethod.CREDIT || outlet.getCreditLimit() <= 0) return;
        long open = open(outlet.getId(), o.getId());
        // возврат экспедитор заберёт при доставке — к долгу добавится заказ минус возврат
        long after = outlet.getDebt() + open + o.getTotal() - o.getReturnTotal();
        if (after <= outlet.getCreditLimit()) return;
        String text = "Долг " + money(outlet.getDebt()) + (open > 0 ? " + не доставлено " + money(open) : "")
                + " + этот заказ " + money(o.getTotal())
                + (o.getReturnTotal() > 0 ? " − возврат " + money(o.getReturnTotal()) : "")
                + " = " + money(after) + " при лимите " + money(outlet.getCreditLimit());
        if (st.isApprovalOverLimit()) {
            o.setStatus(OrderStatus.NEEDS_APPROVAL).setHold(ApprovalKind.LIMIT);
            o.event(now, null, "Система", text + " — нужно разрешение");
        } else {
            o.event(now, null, "Система", text + " — сверх лимита");
        }
    }

    /** Товары заказа для сравнения до и после правки. */
    private static String lines(Order o) {
        return o.getLines().stream().map(l -> l.getProduct().getId() + ":" + l.getQty()).sorted().toList().toString();
    }

    private static String returns(Order o) {
        return o.getReturnLines().stream().map(l -> l.getProduct().getId() + ":" + l.getQty() + ":" + l.getReason())
                .sorted().toList().toString();
    }

    private static String who(Employee e) {
        return e.getName() + " (" + e.getRole().getLabel().toLowerCase() + ")";
    }

    /** Заказы агента за день — телефону: номер, статус и причина отмены видны в приложении. */
    @Transactional(readOnly = true)
    public List<OrderOut> of(Long agentId, LocalDate day) {
        List<Order> list = orders.findByAgentIdAndCreatedAtGreaterThanEqualAndCreatedAtLessThanOrderByCreatedAtAsc(agentId,
                day.atStartOfDay(), day.plusDays(1).atStartOfDay());
        Map<Long, LocalDateTime> delivered = new HashMap<>();
        if (!list.isEmpty()) {
            jdbc.query("""
                    select d.order_id, max(d.delivered_at) at from deliveries d join orders o on o.id = d.order_id
                    where d.company_id = ? and o.agent_id = ? and o.created_at >= ? and o.created_at < ?
                      and d.status in ('DELIVERED', 'PARTIAL')
                    group by d.order_id""", rs -> {
                delivered.put(rs.getLong("order_id"), rs.getTimestamp("at").toLocalDateTime());
            }, list.get(0).getCompanyId(), agentId, day.atStartOfDay(), day.plusDays(1).atStartOfDay());
        }
        return list.stream().map(o -> out(o, delivered.get(o.getId()))).toList();
    }

    /** Последний день до before, когда агент брал заказы (не дальше двух недель); не брал — null. */
    public LocalDate previousDay(Long agentId, Long companyId, LocalDate before) {
        Timestamp at = jdbc.queryForObject("""
                select max(created_at) from orders
                where company_id = ? and agent_id = ? and created_at >= ? and created_at < ?""",
                Timestamp.class, companyId, agentId, before.minusDays(14).atStartOfDay(), before.atStartOfDay());
        return at == null ? null : at.toLocalDateTime().toLocalDate();
    }

    /** В долг, ещё не доставлено — уже будущий долг магазина; кроме заказа except (его правят), null — все. */
    private long open(Long outletId, Long except) {
        Long sum = jdbc.queryForObject("""
                select coalesce(sum(i.qty * i.price - coalesce(i.discount, 0)), 0)
                from orders o join order_items i on i.order_id = o.id
                where o.outlet_id = ? and o.payment_method = 'CREDIT' and o.status in ('ACCEPTED', 'NEEDS_APPROVAL', 'ASSEMBLED', 'IN_TRIP')
                  and o.id <> ?""",
                Long.class, outletId, except == null ? -1L : except);
        return sum == null ? 0 : sum;
    }

    private String number(Long companyId, LocalDate day) {
        String base = "З-" + day.format(NUMBER_DATE) + "-";
        int n = 1;
        while (orders.existsByCompanyIdAndNumber(companyId, base + n)) n++;
        return base + n;
    }

    /** Причину больше не спрашивают — пусто; старые телефоны ещё присылают, сохраняем. */
    private static ReturnReason reason(String raw) {
        if (raw == null || raw.isBlank()) return null;
        try {
            return ReturnReason.valueOf(raw);
        } catch (IllegalArgumentException e) {
            throw new FormException("Неизвестная причина возврата: " + raw);
        }
    }

    private static PaymentMethod payment(String s, CompanySettings st) {
        PaymentMethod p;
        try {
            p = PaymentMethod.valueOf(s);
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new FormException("Неверный способ оплаты — обновите приложение");
        }
        if (p == PaymentMethod.CREDIT && !st.isAllowCredit()) throw new FormException("Продажа в долг выключена — выберите другую оплату");
        if (p == PaymentMethod.KASPI && !st.isAcceptKaspi()) throw new FormException("Kaspi не принимается — выберите другую оплату");
        return p;
    }

    static OrderOut out(Order o) {
        return out(o, null);
    }

    static OrderOut out(Order o, LocalDateTime deliveredAt) {
        String note = switch (o.getStatus()) {
            case NEEDS_APPROVAL -> o.getHold() == ApprovalKind.OVERDUE ? "Заказ закрыт: просрочка — ждёт разрешения директора"
                    : "Долг сверх лимита — ждёт разрешения оператора";
            case CANCELLED, REFUSED -> o.getEvents().isEmpty() ? null : o.getEvents().get(o.getEvents().size() - 1).getText();
            default -> null;
        };
        return new OrderOut(o.getUuid(), o.getOutlet().getId(), o.getNumber(), o.getCreatedAt(), o.getDeliveryDate(),
                o.getPayment().name(), o.getStatus().name(), o.getStatus().getLabel(), note, o.getTotal(),
                o.getLines().stream().map(l -> new LineOut(l.getProduct().getId(), l.getProduct().getName(), l.getQty(),
                        l.getNetPrice(), l.getSum())).toList(),
                o.getReturnTotal(),
                o.getReturnLines().stream().map(l -> new ReturnLineOut(l.getProduct().getId(), l.getProduct().getName(),
                        l.getQty(), l.getPrice(), l.getSum(), ReturnReason.code(l.getReason()))).toList(),
                deliveredAt, o.getComment());
    }

    static String money(long v) {
        return String.format(Locale.ROOT, "%,d", v).replace(',', ' ') + " ₸";
    }

    private static String cut(String s, int max) {
        if (s == null || s.isBlank()) return null;
        s = s.strip();
        return s.length() > max ? s.substring(0, max) : s;
    }
}
