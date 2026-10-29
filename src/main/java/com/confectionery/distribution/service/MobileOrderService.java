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

    /** reason — EXPIRED, DEFECT или PACKAGING. */
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

    /** status — имя OrderStatus; note — для агента: почему ждёт разрешения или отменён; returnTotal — сколько вычтется
     * за возврат. */
    public record OrderOut(UUID uuid, Long outletId, String number, LocalDateTime createdAt, LocalDate deliveryDate,
                           String payment, String status, String statusLabel, String note, long total,
                           List<LineOut> lines, long returnTotal, List<ReturnLineOut> returns) {
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
        PaymentMethod payment = payment(in.payment(), st);
        if (payment == PaymentMethod.CREDIT && outlet.getStatus() == OutletStatus.PENDING)
            throw new FormException("Магазин ещё на проверке — первый заказ без долга: наличные или Kaspi");
        LocalDate delivery = in.deliveryDate() == null ? at.toLocalDate().plusDays(st.getDeliveryDays()) : in.deliveryDate();
        if (delivery.isBefore(at.toLocalDate()) || delivery.isAfter(at.toLocalDate().plusDays(MAX_DELIVERY_DAYS)))
            throw new FormException("Дата доставки — с дня заказа и не дальше " + MAX_DELIVERY_DAYS + " дней");

        Map<Long, Integer> qty = new LinkedHashMap<>();
        for (ItemIn i : in.items()) {
            if (i.productId() == null || i.qty() == null || i.qty() <= 0 || i.qty() > MAX_QTY)
                throw new FormException("Неверное количество товара — проверьте заказ");
            qty.merge(i.productId(), i.qty(), Integer::sum);
        }
        Map<Long, Long> prices = catalog.pricesOn(outlet.getPriceType(), at.toLocalDate());
        Order o = new Order().setUuid(in.uuid()).setOutlet(outlet).setAgent(agent).setCreatedAt(at).setDeliveryDate(delivery)
                .setPayment(payment).setComment(cut(in.comment(), 500)).setNumber(number(agent.getCompanyId(), at.toLocalDate()));
        o.setCompany(agent.getCompany());
        if (in.visitUuid() != null)
            visits.findByUuid(in.visitUuid()).filter(v -> v.getAgent().getId().equals(agentId)).ifPresent(o::setVisit);
        for (Map.Entry<Long, Integer> e : qty.entrySet()) {
            Product p = products.findById(e.getKey()).filter(Product::isActive)
                    .orElseThrow(() -> new FormException("Товар больше не продаётся — обновите данные на телефоне"));
            Long price = prices.get(p.getId());
            if (price == null) throw new FormException("Нет цены на «" + p.getName() + "» — обратитесь к оператору");
            o.addLine(new OrderLine().setProduct(p).setQty(e.getValue()).setPrice(price));
        }
        Set<Long> back = new HashSet<>();
        for (ReturnItemIn r : in.returns() == null ? List.<ReturnItemIn>of() : in.returns()) {
            if (r.productId() == null || r.qty() == null || r.qty() <= 0 || r.qty() > MAX_QTY)
                throw new FormException("Неверное количество в возврате — проверьте возврат");
            if (!back.add(r.productId())) throw new FormException("Товар в возврате дважды — обновите приложение");
            Product p = products.findById(r.productId())
                    .orElseThrow(() -> new FormException("Товар не найден — обновите данные на телефоне"));
            Long price = prices.get(p.getId());
            if (price == null) throw new FormException("Нет цены на «" + p.getName() + "» — обратитесь к оператору");
            o.addReturnLine(new OrderReturnLine().setProduct(p).setQty(r.qty()).setPrice(price).setReason(reason(r.reason())));
        }

        String who = agent.getName() + " (" + agent.getRole().getLabel().toLowerCase() + ")";
        o.setStatus(OrderStatus.ACCEPTED);
        o.event(now, agent, who, "Принят с телефона");
        if (payment == PaymentMethod.CREDIT && outlet.getCreditLimit() > 0) {
            debts.fill(outlet);
            long open = open(outlet.getId());
            // возврат экспедитор заберёт при доставке — к долгу добавится заказ минус возврат
            long after = outlet.getDebt() + open + o.getTotal() - o.getReturnTotal();
            if (after > outlet.getCreditLimit()) {
                String text = "Долг " + money(outlet.getDebt()) + (open > 0 ? " + не доставлено " + money(open) : "")
                        + " + этот заказ " + money(o.getTotal())
                        + (o.getReturnTotal() > 0 ? " − возврат " + money(o.getReturnTotal()) : "")
                        + " = " + money(after) + " при лимите " + money(outlet.getCreditLimit());
                if (st.isApprovalOverLimit()) {
                    o.setStatus(OrderStatus.NEEDS_APPROVAL);
                    o.event(now, null, "Система", text + " — нужно разрешение");
                } else {
                    o.event(now, null, "Система", text + " — сверх лимита");
                }
            }
        }
        return out(orders.save(o));
    }

    /** Заказы агента за день — телефону: номер, статус и причина отмены видны в приложении. */
    @Transactional(readOnly = true)
    public List<OrderOut> of(Long agentId, LocalDate day) {
        return orders.findByAgentIdAndCreatedAtGreaterThanEqualAndCreatedAtLessThanOrderByCreatedAtAsc(agentId,
                day.atStartOfDay(), day.plusDays(1).atStartOfDay()).stream().map(MobileOrderService::out).toList();
    }

    /** В долг, ещё не доставлено — уже будущий долг магазина. */
    private long open(Long outletId) {
        Long sum = jdbc.queryForObject("""
                select coalesce(sum(i.qty * i.price - coalesce(i.discount, 0)), 0)
                from orders o join order_items i on i.order_id = o.id
                where o.outlet_id = ? and o.payment_method = 'CREDIT' and o.status in ('ACCEPTED', 'NEEDS_APPROVAL', 'ASSEMBLED', 'IN_TRIP')""",
                Long.class, outletId);
        return sum == null ? 0 : sum;
    }

    private String number(Long companyId, LocalDate day) {
        String base = "З-" + day.format(NUMBER_DATE) + "-";
        int n = 1;
        while (orders.existsByCompanyIdAndNumber(companyId, base + n)) n++;
        return base + n;
    }

    private static ReturnReason reason(String raw) {
        try {
            return ReturnReason.valueOf(raw);
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new FormException("Укажите причину возврата: просрочка, брак или упаковка");
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
        String note = switch (o.getStatus()) {
            case NEEDS_APPROVAL -> "Долг сверх лимита — ждёт разрешения оператора";
            case CANCELLED, REFUSED -> o.getEvents().isEmpty() ? null : o.getEvents().get(o.getEvents().size() - 1).getText();
            default -> null;
        };
        return new OrderOut(o.getUuid(), o.getOutlet().getId(), o.getNumber(), o.getCreatedAt(), o.getDeliveryDate(),
                o.getPayment().name(), o.getStatus().name(), o.getStatus().getLabel(), note, o.getTotal(),
                o.getLines().stream().map(l -> new LineOut(l.getProduct().getId(), l.getProduct().getName(), l.getQty(),
                        l.getNetPrice(), l.getSum())).toList(),
                o.getReturnTotal(),
                o.getReturnLines().stream().map(l -> new ReturnLineOut(l.getProduct().getId(), l.getProduct().getName(),
                        l.getQty(), l.getPrice(), l.getSum(), l.getReason().name())).toList());
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
