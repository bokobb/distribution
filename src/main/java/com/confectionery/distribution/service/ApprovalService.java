package com.confectionery.distribution.service;

import com.confectionery.distribution.admin.Fmt;
import com.confectionery.distribution.domain.Approval;
import com.confectionery.distribution.domain.ApprovalKind;
import com.confectionery.distribution.domain.CompanySettings;
import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.OutletStatus;
import com.confectionery.distribution.domain.PaymentMethod;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.repository.ApprovalRepository;
import com.confectionery.distribution.repository.OrderRepository;
import com.confectionery.distribution.repository.OutletRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Array;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * «Разрешения»: что ждёт решения руководителя и что решили сегодня.
 *
 * <p>Ждут решения заказы «Нужно разрешение» (долг сверх лимита или магазин закрыт по просрочке), магазины
 * «На проверке» и недоплаты при выдаче. Заказы и магазины — по своему статусу, поэтому правка заказа торговым или
 * проверка магазина в его карточке сами убирают их отсюда; недоплата ждёт в таблице approvals. Каждое решение
 * записывается в approvals — из неё «Решено сегодня» и «Вернуть».
 *
 * <p>Ключ разрешения: «o» + id заказа, «s» + id магазина, «u» + id недоплаты.
 */
@Service
@RequiredArgsConstructor
public class ApprovalService {

    private final OrderRepository orders;
    private final OutletRepository outlets;
    private final ApprovalRepository approvals;
    private final SettingsService settings;
    private final DebtService debts;
    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final Fmt fmt;

    /** Строка расчёта; total — итог (выделяется). */
    public record Term(String label, String value, boolean total) {
    }

    /** Кнопка решения. style — primary, line или danger; allowed = false — кнопка видна, но решает другой. */
    public record Act(String code, String label, String style, boolean allowed) {
    }

    public record Item(String key, ApprovalKind kind, String company, Long outletId, String outlet, String address,
                       String phone, Long orderId, String title, String who, LocalDateTime at, List<Term> terms,
                       String note, List<String> facts, boolean facade, List<Act> acts, String hint) {
        /** Подпись под расчётом красная, когда правило нарушено. */
        public boolean noteBad() {
            return note != null && !note.contains("в пределах");
        }
    }

    /** Решено сегодня: магазин, что решили, кто и когда; undo — можно «Вернуть». */
    public record Done(Long id, String outlet, String text, boolean deny, String who, LocalDateTime at, boolean undo) {
    }

    public record Page(List<Item> items, List<Done> today) {
        public long money() {
            return items.stream().filter(i -> i.kind().money()).count();
        }

        public long shops() {
            return items.size() - money();
        }
    }

    /** Всё, что ждёт решения, — для компании (companyId) или всех компаний владельца (null). */
    @Transactional(readOnly = true)
    public Page page(Long companyId, Role role) {
        Map<Long, CompanySettings> st = new HashMap<>();
        List<Item> items = new ArrayList<>();

        List<Order> waiting = orders.findByStatusOrderByCreatedAtAsc(OrderStatus.NEEDS_APPROVAL);
        List<Outlet> shops = waiting.stream().map(Order::getOutlet).distinct().toList();
        debts.fill(shops);
        Map<Long, List<Open>> open = openCredit(shops.stream().map(Outlet::getId).toArray(Long[]::new));
        for (Order o : waiting) {
            CompanySettings s = st.computeIfAbsent(o.getCompanyId(), settings::of);
            items.add(o.getHold() == ApprovalKind.OVERDUE ? overdue(o, s, role) : limit(o, open.getOrDefault(o.getOutlet().getId(), List.of())));
        }

        for (Approval a : approvals.findByKindAndDecisionIsNullOrderByCreatedAtAsc(ApprovalKind.UNDERPAY))
            items.add(underpay(a));

        List<Outlet> pending = outlets.findByStatusOrderByIdAsc(OutletStatus.PENDING);
        Long[] ids = pending.stream().map(Outlet::getId).toArray(Long[]::new);
        Map<Long, String> firstOrder = new HashMap<>();
        Map<Long, LocalDateTime> asked = new HashMap<>();
        if (ids.length > 0) {
            query("""
                    select distinct on (o.outlet_id) o.outlet_id, o.number, o.payment_method,
                           (select coalesce(sum(i.qty * i.price - coalesce(i.discount, 0)), 0) from order_items i where i.order_id = o.id)
                    from orders o where o.outlet_id = any(?) and o.status <> 'CANCELLED'
                    order by o.outlet_id, o.created_at""", ids, rs -> firstOrder.put(rs.getLong(1),
                    "Первый заказ " + rs.getString(2) + " · " + money(rs.getLong(4)) + " · "
                            + PaymentMethod.valueOf(rs.getString(3)).getLabel().toLowerCase()));
            query("""
                    select outlet_id, max(decided_at) from approvals
                    where kind = 'OUTLET' and decision = 'INFO' and outlet_id = any(?) group by outlet_id""", ids,
                    rs -> asked.put(rs.getLong(1), rs.getTimestamp(2).toLocalDateTime()));
        }
        for (Outlet s : pending) items.add(outlet(s, firstOrder.get(s.getId()), asked.get(s.getId())));

        items.sort(Comparator.comparing(Item::at, Comparator.nullsLast(Comparator.reverseOrder())));
        return new Page(items, today());
    }


    private Item limit(Order o, List<Open> open) {
        Outlet s = o.getOutlet();
        List<Open> others = open.stream().filter(x -> !x.orderId().equals(o.getId())).toList();
        long notDelivered = others.stream().mapToLong(Open::sum).sum();
        long self = o.getTotal() - o.getReturnTotal();
        long after = s.getDebt() + notDelivered + self;
        List<Term> terms = List.of(new Term("Долг сейчас", money(s.getDebt()), false),
                new Term("+ не доставлено в долг", money(notDelivered), false),
                new Term(o.getReturnTotal() > 0 ? "+ этот заказ − возврат" : "+ этот заказ", money(self), false),
                new Term("= станет", money(after), true));
        String note = "лимит " + money(s.getCreditLimit())
                + (after > s.getCreditLimit() ? " · сверх на " + money(after - s.getCreditLimit()) : " · уже в пределах лимита");
        List<String> facts = new ArrayList<>();
        facts.add(s.getOverdue() > 0 ? "Просрочено " + money(s.getOverdue()) + ", " + s.getOverdueDays() + " дн." : "Просрочки нет");
        facts.add(lastPayment(s));
        if (!others.isEmpty())
            facts.add("не доставлено: " + String.join(", ", others.stream().map(Open::number).toList()));
        List<Act> acts = new ArrayList<>();
        acts.add(new Act("OK", "Разрешить заказ", "primary", true));
        if (o.getPayment() == PaymentMethod.CREDIT) acts.add(new Act("CASH", "Только оплата при доставке", "line", true));
        acts.add(new Act("DENY", "Отказать", "danger", true));
        return new Item("o" + o.getId(), ApprovalKind.LIMIT, o.getCompany().getName(), s.getId(), s.getName(), s.getAddress(),
                s.getPhone(), o.getId(), orderTitle(o), agentName(o), o.getCreatedAt(), terms, note, facts, false, acts, null);
    }

    private Item overdue(Order o, CompanySettings st, Role role) {
        Outlet s = o.getOutlet();
        List<Term> terms = List.of(new Term("Просрочено", money(s.getOverdue()), true),
                new Term("Дней", String.valueOf(s.getOverdueDays()), true),
                new Term("Долг", money(s.getDebt()), false),
                new Term("Лимит", s.getCreditLimit() > 0 ? money(s.getCreditLimit()) : "без долга", false));
        String note = "правило: больше " + st.getOverdueDays() + " дней или больше " + money(st.getOverdueAmount());
        boolean can = st.unblocks(role);
        List<Act> acts = new ArrayList<>();
        acts.add(new Act("OK", "Разрешить один заказ", "primary", can));
        acts.add(new Act("DENY", "Отказать", "danger", true));
        return new Item("o" + o.getId(), ApprovalKind.OVERDUE, o.getCompany().getName(), s.getId(), s.getName(), s.getAddress(),
                s.getPhone(), o.getId(), orderTitle(o), agentName(o), o.getCreatedAt(), terms, note, List.of(lastPayment(s)),
                false, acts, can ? null : "Один заказ открывает " + st.unblockersText());
    }

    private Item underpay(Approval a) {
        Outlet s = a.getOutlet();
        List<Term> terms = new ArrayList<>();
        String[] rows = a.getTerms() == null ? new String[0] : a.getTerms().split("\n");
        for (int i = 0; i < rows.length; i++) {
            String[] kv = rows[i].split("=", 2);
            terms.add(new Term(kv[0], kv.length > 1 ? kv[1] : "", i >= rows.length - 2));
        }
        String agent = s.getAgent() == null ? null : s.getAgent().getName();
        List<Act> acts = List.of(new Act("OK", "Записать в долг магазина", "primary", true),
                new Act("TASK", agent == null ? "Забрать при следующем визите" : "Торговому — забрать завтра", "line", true));
        return new Item("u" + a.getId(), ApprovalKind.UNDERPAY, a.getCompany().getName(), s.getId(), s.getName(),
                s.getAddress(), s.getPhone(), a.getOrder() == null ? null : a.getOrder().getId(), a.getTitle(),
                a.getCreatedBy(), a.getCreatedAt(), terms, a.getNote(), List.of("Товар уже выдан"), false, acts, null);
    }

    private Item outlet(Outlet s, String firstOrder, LocalDateTime asked) {
        LocalDate since = s.getCreatedAt() == null ? LocalDate.now(clock) : s.getCreatedAt();
        long days = ChronoUnit.DAYS.between(since, LocalDate.now(clock));
        String title = firstOrder != null ? firstOrder
                : "Заказов пока нет" + (days > 0 ? " · ждёт проверки " + fmt.plural(days, "день", "дня", "дней") : "");
        List<String> facts = new ArrayList<>();
        String who = fmt.dot(s.getLegal(), s.getOwner() == null ? null : "владелец " + s.getOwner(), fmt.phone(s.getPhone()),
                s.getBin() == null ? null : "БИН " + s.getBin());
        if (!who.isBlank()) facts.add(who);
        facts.add(s.getLat() == null ? "точки на карте нет" : "точка на карте есть");
        facts.add(s.getFacadePhoto() == null ? "фото фасада нет" : "фото фасада есть");
        if (asked != null) facts.add("данные запрошены " + fmt.when(asked));
        List<Act> acts = new ArrayList<>();
        acts.add(new Act("OK", "Проверен — работать", "primary", true));
        if (asked == null) acts.add(new Act("INFO", "Нужны данные", "line", true));
        return new Item("s" + s.getId(), ApprovalKind.OUTLET, s.getCompany().getName(), s.getId(), s.getName(),
                s.getAddress(), s.getPhone(), null, title, s.getCreatedBy() == null ? (s.getAgent() == null ? "—" : s.getAgent().getName()) : s.getCreatedBy(),
                since.atStartOfDay(), List.of(), null, facts, s.getFacadePhoto() != null, acts, null);
    }

    /** Решено сегодня — новые сверху. */
    private List<Done> today() {
        LocalDateTime from = LocalDate.now(clock).atStartOfDay();
        return approvals.findByDecidedAtGreaterThanEqualOrderByDecidedAtDesc(from).stream()
                .map(a -> new Done(a.getId(), a.getOutlet().getName(), a.getDecisionText(), "DENY".equals(a.getDecision()),
                        a.getDecidedBy(), a.getDecidedAt(), true))
                .toList();
    }

    /**
     * Решение по разрешению key. code — OK, CASH, DENY (заказ), OK, TASK (недоплата), OK, INFO (новый магазин).
     * Уже решено другим — FormException с понятной причиной. Возвращает, что сделано.
     */
    @Transactional
    public String decide(String key, String code, Actor actor, Role role) {
        LocalDateTime now = LocalDateTime.now(clock);
        Long id = id(key);
        return switch (key.charAt(0)) {
            case 'o' -> decideOrder(id, code, actor, role, now);
            case 'u' -> decideUnderpay(id, code, actor, now);
            case 's' -> decideOutlet(id, code, actor, now);
            default -> throw new NotFoundException();
        };
    }

    private String decideOrder(Long id, String code, Actor actor, Role role, LocalDateTime now) {
        Order o = orders.lockAll(List.of(id)).stream().findFirst().orElseThrow(NotFoundException::new);
        if (o.getStatus() != OrderStatus.NEEDS_APPROVAL)
            throw new FormException("Заказ " + o.getNumber() + " уже «" + o.getStatus().getLabel() + "» — решать не нужно");
        ApprovalKind kind = o.getHold() == null ? ApprovalKind.LIMIT : o.getHold();
        Outlet s = o.getOutlet();
        Approval a = log(kind, s, o, orderTitle(o), code, actor, now);
        String text;
        switch (code) {
            case "OK" -> {
                if (kind == ApprovalKind.OVERDUE) {
                    CompanySettings st = settings.of(o.getCompanyId());
                    if (!st.unblocks(role)) throw new FormException("Один заказ при просрочке открывает " + st.unblockersText());
                    text = "Разрешён один заказ " + o.getNumber();
                } else {
                    text = "Разрешён заказ " + o.getNumber();
                }
                o.setStatus(OrderStatus.ACCEPTED);
                o.event(now, actor.entity(), actor.who(), kind == ApprovalKind.OVERDUE
                        ? "Разрешил один заказ при просрочке" : "Разрешил заказ сверх лимита долга");
            }
            case "CASH" -> {
                if (kind != ApprovalKind.LIMIT || o.getPayment() != PaymentMethod.CREDIT) throw new FormException("Заказ и так не в долг");
                a.setPrevPayment(o.getPayment());
                o.setPayment(PaymentMethod.CASH).setStatus(OrderStatus.ACCEPTED);
                o.event(now, actor.entity(), actor.who(), "Сверх лимита: переведён на оплату при доставке");
                text = "Заказ " + o.getNumber() + " — только оплата при доставке";
            }
            case "DENY" -> {
                String why = kind == ApprovalKind.OVERDUE ? "просрочка " + overdueDays(s) + " дн." : "долг сверх лимита";
                o.setStatus(OrderStatus.CANCELLED);
                o.event(now, actor.entity(), actor.who(), "Отказано: " + why);
                text = "Отказано: " + why;
            }
            default -> throw new FormException("Неизвестное решение");
        }
        a.setDecisionText(text);
        approvals.save(a);
        return quoted(s.getName()) + " — " + text;
    }

    private String decideUnderpay(Long id, String code, Actor actor, LocalDateTime now) {
        Approval a = approvals.findById(id).orElseThrow(NotFoundException::new);
        if (a.getDecision() != null) throw new FormException("Уже решено: " + a.getDecisionText());
        String missing = a.getTerms() == null ? "" : a.getTerms().lines().filter(l -> l.startsWith("Не хватает="))
                .map(l -> l.substring("Не хватает=".length())).findFirst().orElse("");
        String agent = a.getOutlet().getAgent() == null ? null : a.getOutlet().getAgent().getName();
        String text = switch (code) {
            case "OK" -> "Недоплата " + missing + " — в долг магазина";
            case "TASK" -> agent == null ? "Недоплату " + missing + " забрать при следующем визите"
                    : "Недоплату " + missing + " забрать завтра: поручено " + agent;
            default -> throw new FormException("Неизвестное решение");
        };
        a.setDecision(code).setDecisionText(text).setDecidedAt(now).setDecidedBy(actor.who());
        if (a.getOrder() != null) a.getOrder().event(now, actor.entity(), actor.who(), text);
        return quoted(a.getOutlet().getName()) + " — " + text;
    }

    private String decideOutlet(Long id, String code, Actor actor, LocalDateTime now) {
        Outlet s = outlets.findById(id).orElseThrow(NotFoundException::new);
        if (s.getStatus() != OutletStatus.PENDING) throw new FormException("Магазин «" + s.getName() + "» уже проверен");
        Approval a = log(ApprovalKind.OUTLET, s, null, "Новый магазин", code, actor, now);
        String text = switch (code) {
            case "OK" -> {
                s.setStatus(OutletStatus.ACTIVE);
                yield "Магазин проверен" + (s.getCreditLimit() > 0 ? ": лимит " + money(s.getCreditLimit()) : "");
            }
            case "INFO" -> "Нужны данные" + (s.getAgent() == null ? "" : ": запрос торговому " + s.getAgent().getName());
            default -> throw new FormException("Неизвестное решение");
        };
        a.setDecisionText(text);
        approvals.save(a);
        return quoted(s.getName()) + " — " + text;
    }

    /**
     * «Вернуть» решение, принятое сегодня: заказ снова ждёт разрешения (если его ещё не собрали), недоплата и магазин —
     * снова ждут решения.
     */
    @Transactional
    public String undo(Long approvalId, Actor actor) {
        Approval a = approvals.findById(approvalId).orElseThrow(NotFoundException::new);
        LocalDateTime now = LocalDateTime.now(clock);
        if (a.getDecidedAt() == null || a.getDecidedAt().isBefore(now.toLocalDate().atStartOfDay()))
            throw new FormException("Вернуть можно только сегодняшнее решение");
        String name = quoted(a.getOutlet().getName());
        switch (a.getKind()) {
            case LIMIT, OVERDUE -> {
                Order o = orders.lockAll(List.of(a.getOrder().getId())).get(0);
                OrderStatus expected = "DENY".equals(a.getDecision()) ? OrderStatus.CANCELLED : OrderStatus.ACCEPTED;
                if (o.getStatus() != expected)
                    throw new FormException("Заказ " + o.getNumber() + " уже «" + o.getStatus().getLabel() + "» — вернуть нельзя");
                o.setStatus(OrderStatus.NEEDS_APPROVAL).setHold(a.getKind());
                if (a.getPrevPayment() != null) o.setPayment(a.getPrevPayment());
                o.event(now, actor.entity(), actor.who(), "Вернул на разрешение (было: " + a.getDecisionText() + ")");
                approvals.delete(a);
            }
            case UNDERPAY -> {
                if (a.getOrder() != null)
                    a.getOrder().event(now, actor.entity(), actor.who(), "Вернул недоплату на разрешение");
                a.setDecision(null).setDecisionText(null).setDecidedAt(null).setDecidedBy(null);
            }
            case OUTLET -> {
                Outlet s = a.getOutlet();
                if ("OK".equals(a.getDecision())) {
                    if (s.getStatus() != OutletStatus.ACTIVE)
                        throw new FormException("Магазин уже «" + s.getStatus().getLabel() + "» — вернуть нельзя");
                    s.setStatus(OutletStatus.PENDING);
                }
                approvals.delete(a);
            }
        }
        return name + " — снова ждёт решения";
    }

    /** Недоплата при выдаче: долг магазина станет больше лимита или у магазина нет продажи в долг — на разрешение. */
    @Transactional
    public void underpay(Order o, long given, long paid, long debtBefore, CompanySettings st, Actor actor, LocalDateTime at) {
        if (!st.isUnderpayApproval() || paid >= given) return;
        Outlet s = o.getOutlet();
        long missing = given - paid, after = debtBefore + missing;
        boolean noCredit = !st.isAllowCredit() || s.getCreditLimit() <= 0;
        if (!noCredit && after <= s.getCreditLimit()) return;
        String trip = o.getTrip() == null ? "" : " · рейс " + o.getTrip().getNumber();
        Approval a = new Approval().setKind(ApprovalKind.UNDERPAY).setOutlet(s).setOrder(o)
                .setTitle("Заказ " + o.getNumber() + " · " + money(given) + trip)
                .setTerms(String.join("\n", "Выдано=" + money(given), "Оплачено=" + money(paid),
                        "Не хватает=" + money(missing), "Долг станет=" + money(after)))
                .setNote(noCredit ? "у магазина нет продажи в долг"
                        : "лимит " + money(s.getCreditLimit()) + " · сверх на " + money(after - s.getCreditLimit()))
                .setCreatedAt(at).setCreatedBy(actor.who());
        a.setCompany(o.getCompany());
        approvals.save(a);
        o.event(at, null, "Система", "Недоплата " + money(missing) + " — на разрешение");
    }

    private Approval log(ApprovalKind kind, Outlet s, Order o, String title, String code, Actor actor, LocalDateTime now) {
        Approval a = new Approval().setKind(kind).setOutlet(s).setOrder(o).setTitle(title).setCreatedAt(now)
                .setCreatedBy(actor.who()).setDecision(code).setDecidedAt(now).setDecidedBy(actor.who());
        a.setCompany(s.getCompany());
        return a;
    }

    private int overdueDays(Outlet s) {
        debts.fill(s);
        return s.getOverdueDays();
    }

    private String orderTitle(Order o) {
        return "Заказ " + o.getNumber() + " · " + money(o.getTotal()) + " · " + o.getPayment().getLabel().toLowerCase();
    }

    /** Название в кавычках, если своих кавычек в нём нет: «Баян», но Магазин «Мерей». */
    public static String quoted(String name) {
        return name == null || name.contains("«") || name.contains("\"") ? name : "«" + name + "»";
    }

    /** Суммы — как в истории заказа: «16 300 ₸». */
    private static String money(long v) {
        return MobileOrderService.money(v);
    }

    private static String agentName(Order o) {
        return o.getAgent() == null ? "—" : o.getAgent().getName();
    }

    private String lastPayment(Outlet s) {
        return s.getLastPaymentDate() == null ? "оплат ещё не было"
                : "последняя оплата " + fmt.day(s.getLastPaymentDate()) + ", " + money(s.getLastPaymentSum());
    }

    private record Open(Long orderId, String number, long sum) {
    }

    /** В долг, ещё не доставлено — по магазинам; как в проверке лимита при заказе. */
    private Map<Long, List<Open>> openCredit(Long[] outletIds) {
        Map<Long, List<Open>> out = new HashMap<>();
        if (outletIds.length == 0) return out;
        query("""
                select o.outlet_id, o.id, o.number, coalesce(sum(i.qty * i.price - coalesce(i.discount, 0)), 0)
                from orders o join order_items i on i.order_id = o.id
                where o.outlet_id = any(?) and o.payment_method = 'CREDIT'
                  and o.status in ('ACCEPTED', 'NEEDS_APPROVAL', 'ASSEMBLED', 'IN_TRIP')
                group by o.outlet_id, o.id, o.number order by o.id""", outletIds,
                rs -> out.computeIfAbsent(rs.getLong(1), k -> new ArrayList<>()).add(new Open(rs.getLong(2), rs.getString(3), rs.getLong(4))));
        return out;
    }

    /** Магазины, которым сегодня открыли один заказ при просрочке. */
    public java.util.Set<Long> unblockedToday() {
        return new java.util.HashSet<>(jdbc.queryForList("select outlet_id from approvals where kind = 'OVERDUE' and decision = 'OK' and decided_at >= ?",
                Long.class, LocalDate.now(clock).atStartOfDay()));
    }

    /** Подпись под статусом в списке заказов: чем кончилось разрешение по заказу — «сверх лимита — разрешён», «разрешён 1 заказ». */
    public Map<Long, String> orderNotes(List<Order> list) {
        Map<Long, String> out = new HashMap<>();
        Long[] ids = list.stream().map(Order::getId).toArray(Long[]::new);
        if (ids.length == 0) return out;
        query("""
                select order_id, kind, decision from approvals
                where order_id = any(?) and decision is not null order by decided_at, id""", ids, rs -> {
            String code = rs.getString(3);
            String note = switch (ApprovalKind.valueOf(rs.getString(2))) {
                case LIMIT -> "CASH".equals(code) ? "сверх лимита — только при доставке" : "сверх лимита — разрешён";
                case OVERDUE -> "разрешён 1 заказ";
                case UNDERPAY -> "OK".equals(code) ? "недоплата — в долг магазина" : "недоплату заберёт торговый";
                case OUTLET -> null;
            };
            if (note != null && !"DENY".equals(code)) out.put(rs.getLong(1), note);
        });
        query("select order_id from approvals where order_id = any(?) and kind = 'UNDERPAY' and decision is null", ids,
                rs -> out.put(rs.getLong(1), "недоплата ждёт решения"));
        for (Order o : list) {
            if (out.containsKey(o.getId())) continue;
            if (o.getStatus() == OrderStatus.NEEDS_APPROVAL && o.getHold() != null) out.put(o.getId(), o.getHold().getLabel().toLowerCase());
            else if ((o.getStatus() == OrderStatus.CANCELLED || o.getStatus() == OrderStatus.REFUSED) && o.getRefuseReason() != null)
                out.put(o.getId(), o.getRefuseReason());
            else if (o.getOutlet().getStatus() == OutletStatus.PENDING) out.put(o.getId(), "новый магазин");
        }
        return out;
    }

    private void query(String sql, Long[] ids, org.springframework.jdbc.core.RowCallbackHandler row) {
        jdbc.query(sql, ps -> {
            Array arr = ps.getConnection().createArrayOf("bigint", ids);
            ps.setArray(1, arr);
        }, row);
    }

    private static Long id(String key) {
        try {
            return Long.valueOf(key.substring(1));
        } catch (RuntimeException e) {
            throw new NotFoundException();
        }
    }
}
