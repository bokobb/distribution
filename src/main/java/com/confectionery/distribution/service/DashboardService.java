package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Сводки для дашборда (и будущего блока на главном экране CRM). Данные дня загружаются один раз
 * ({@link #snapshot()}), дальше снимок считает цифры по компании или по всем.
 */
@Service
@RequiredArgsConstructor
public class DashboardService {

    private final CompanyService companies;
    private final OutletService outlets;
    private final OrderRepository orders;
    private final TripService trips;
    private final ProductReturnRepository returns;
    private final ReceiptRepository receipts;
    private final VisitRepository visits;
    private final StaffService staff;
    private final SettingsService settings;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    private static final DateTimeFormatter HM = DateTimeFormatter.ofPattern("HH:mm");
    private static final DateTimeFormatter DM = DateTimeFormatter.ofPattern("dd.MM");

    /**
     * Главные цифры дня: выдано (заказов на сегодня всего, рейсов в пути), ждут отгрузки, не сдано в кассу (из них
     * в пути и недостача, ждущая решения), долги (магазинов с просрочкой), возвраты негодного (чаще всего какой товар).
     */
    public record Summary(long deliveredToday, int deliveredStops, long waitingSum, int waitingOrders,
                          long cashOnHands, int openTrips, long debts, long overdue, long returnsToday,
                          int returnsQty, int needsApproval, int pendingOutlets, int todayOrders, int onRoad,
                          long cashOnRoad, long shortage, int overdueOutlets, String topReturn) {
        /** Возвраты в процентах от выданного за день, «7,5». */
        public String returnsPercent() {
            double v = deliveredToday == 0 ? 0 : returnsToday * 100.0 / deliveredToday;
            return String.format(Locale.forLanguageTag("ru"), "%.1f", v);
        }
    }

    /** Торговый за сегодня: заказы, новые магазины, визиты без заказа; link — связь и рабочий день. */
    public record AgentRow(Employee agent, int orders, long sum, int refusals, int newOutlets, String link) {
        public boolean stale() {
            return agent.isStale();
        }

        public String initials() {
            String[] p = agent.getName().strip().split("\\s+");
            return (p[0].substring(0, 1) + (p.length > 1 ? p[1].substring(0, 1) : "")).toUpperCase(Locale.ROOT);
        }
    }

    /** Что требует внимания: tone — warn / info / bad; sub — подробности, action — кнопка, ведущая на href. */
    public record Alert(String tone, String text, String sub, String action, String href) {
    }

    /** Магазин без визита STALE_DAYS+ дней: торговый, адрес, сколько дней. */
    public record StaleOutlet(Outlet outlet, int days) {
    }

    public record CompanyRow(Company company, Summary summary, int agents, int expeditors, int outlets) {
    }

    /** Возвраты негодного по товарам (для отчёта о качестве). */
    public record QualityRow(String product, int qty, long sum) {
    }

    public Snapshot snapshot() {
        return new Snapshot();
    }

    public List<QualityRow> quality(Long cid) {
        return quality(returns.findAll(), cid);
    }

    private static List<QualityRow> quality(List<ProductReturn> list, Long cid) {
        Map<String, QualityRow> m = new LinkedHashMap<>();
        for (ProductReturn r : list) {
            if (cid != null && !cid.equals(r.getCompanyId())) continue;
            for (ReturnLine l : r.getLines()) {
                String k = l.getProduct().getName();
                QualityRow q = m.get(k);
                m.put(k, new QualityRow(k, (q == null ? 0 : q.qty()) + l.getQty(), (q == null ? 0 : q.sum()) + l.getSum()));
            }
        }
        return m.values().stream().sorted(Comparator.comparingInt(QualityRow::qty).reversed()).toList();
    }

    /** Данные дня, загруженные один раз. Методы принимают cid: null — все видимые компании. */
    public class Snapshot {
        private final LocalDate today = LocalDate.now(clock);
        /** Отгруженные на сегодня и дальше и все ещё не отгруженные (у них дата — день заказа). */
        private final List<Order> upcoming = java.util.stream.Stream.concat(orders.findByDeliveryDateGreaterThanEqual(today).stream(),
                orders.findByStatusIn(EnumSet.of(OrderStatus.ACCEPTED, OrderStatus.ASSEMBLED, OrderStatus.NEEDS_APPROVAL)).stream()).distinct().toList();
        private final List<Order> createdToday = orders.findByCreatedAtGreaterThanEqualAndCreatedAtLessThan(
                today.atStartOfDay(), today.plusDays(1).atStartOfDay());
        private final List<Trip> tripList = trips.current(null);
        private final List<ProductReturn> returnsToday = returns.findByDate(today);
        private final List<Outlet> outletList = outlets.list(null);
        private final List<Receipt> receiptList = receipts.findAllByOrderByDateDescIdDesc();
        private final List<Visit> visitsToday = visits.findByStartedAtGreaterThanEqualAndStartedAtLessThan(
                today.atStartOfDay(), today.plusDays(1).atStartOfDay());
        private final List<Employee> people = staff.employees(null);
        private Map<Long, LocalDate> lastVisit;
        private Map<String, LocalDateTime> dayEvents;

        private <T extends CompanyEntity> List<T> of(List<T> list, Long cid) {
            return cid == null ? list : list.stream().filter(x -> cid.equals(x.getCompanyId())).toList();
        }

        public List<Trip> trips(Long cid) {
            return of(tripList, cid);
        }

        public Summary summary(Long cid) {
            List<Order> os = of(upcoming, cid);
            List<Order> delivered = os.stream().filter(o -> today.equals(o.getDeliveryDate()) && o.getStatus().delivered()).toList();
            List<Order> waiting = os.stream().filter(o -> o.getStatus().waiting()).toList();
            List<Trip> open = of(tripList, cid).stream().filter(t -> t.getStatus().cashOnHands()).toList();
            List<ProductReturn> rs = of(returnsToday, cid);
            List<Outlet> ol = of(outletList, cid);
            List<Trip> ts = of(tripList, cid);
            Map<String, Integer> byProduct = new HashMap<>();
            rs.forEach(r -> r.getLines().forEach(l -> byProduct.merge(l.getProduct().getName(), l.getQty(), Integer::sum)));
            String top = byProduct.entrySet().stream().max(Map.Entry.comparingByValue()).map(Map.Entry::getKey).orElse(null);
            return new Summary(
                    delivered.stream().mapToLong(Order::getDeliveredTotal).sum(), delivered.size(),
                    waiting.stream().mapToLong(Order::getTotal).sum(), waiting.size(),
                    open.stream().mapToLong(Trip::getCash).sum(), open.size(),
                    ol.stream().mapToLong(o -> Math.max(0, o.getDebt())).sum(), ol.stream().mapToLong(Outlet::getOverdue).sum(),
                    rs.stream().mapToLong(ProductReturn::getTotal).sum(), rs.stream().mapToInt(ProductReturn::getQty).sum(),
                    (int) os.stream().filter(o -> o.getStatus() == OrderStatus.NEEDS_APPROVAL).count(),
                    (int) ol.stream().filter(o -> o.getStatus() == OutletStatus.PENDING).count(),
                    (int) os.stream().filter(o -> today.equals(o.getDeliveryDate()) && o.getTrip() != null && o.getStatus() != OrderStatus.CANCELLED).count(),
                    (int) ts.stream().filter(t -> t.getStatus() == TripStatus.ON_ROAD).count(),
                    ts.stream().filter(t -> t.getStatus() == TripStatus.ON_ROAD).mapToLong(Trip::getCash).sum(),
                    ts.stream().filter(Trip::isShortageWaiting).mapToLong(t -> -t.getCashDiff()).sum(),
                    (int) ol.stream().filter(o -> o.getOverdue() > 0).count(), top);
        }

        /** Агенты: заказы сегодня (доставка завтра), визиты, отказы — визиты без заказа. */
        public List<AgentRow> agents(Long cid) {
            List<AgentRow> out = new ArrayList<>();
            for (Employee a : of(people, cid)) {
                if (a.getRole() != Role.AGENT) continue;
                List<Visit> vs = visitsToday.stream().filter(v -> a.equals(v.getAgent())).toList();
                a.setVisitedToday(vs.size());
                List<Order> taken = createdToday.stream().filter(o -> a.equals(o.getAgent())).toList();
                int refusals = (int) vs.stream().filter(v -> v.getResult() == VisitResult.NO_ORDER).count();
                int fresh = (int) outletList.stream().filter(o -> today.equals(o.getCreatedAt()) && a.equals(o.getAgent())).count();
                out.add(new AgentRow(a, taken.size(), taken.stream().mapToLong(Order::getTotal).sum(), refusals, fresh, link(a)));
            }
            out.sort(Comparator.comparingLong(AgentRow::sum).reversed());
            return out;
        }

        /** «Требует внимания сейчас»: что решить, принять или проверить — с кнопкой. */
        public List<Alert> alerts(Long cid) {
            List<Alert> out = new ArrayList<>();
            Summary s = summary(cid);
            int underpay = jdbc.queryForObject("select count(*) from approvals where decision is null and kind = 'UNDERPAY'"
                    + " and (cast(? as bigint) is null or company_id = ?)", Integer.class, cid, cid);
            int approvals = s.needsApproval() + s.pendingOutlets() + underpay;
            if (approvals > 0)
                out.add(new Alert("warn", plural(approvals, "разрешение ждёт", "разрешения ждут", "разрешений ждут") + " решения",
                        dot(s.needsApproval() > 0 ? "заказы сверх лимита и при просрочке: " + s.needsApproval() : null,
                                underpay > 0 ? "недоплата: " + underpay : null,
                                s.pendingOutlets() > 0 ? plural(s.pendingOutlets(), "новый магазин", "новых магазина", "новых магазинов") : null),
                        "Решить", "/admin/approvals"));
            for (Trip t : of(tripList, cid)) {
                if (t.isShortageWaiting())
                    out.add(new Alert("bad", "Недостача " + money(-t.getCashDiff()) + " — " + t.getExpeditor().getName(),
                            t.getCompany().getName() + " · рейс " + t.getNumber() + " закроет директор или владелец", "Открыть", "/admin/cash/" + t.getId()));
            }
            List<Trip> waiting = of(tripList, cid).stream().filter(t -> t.isWaitingCash() && !t.isShortageWaiting()).toList();
            if (!waiting.isEmpty())
                out.add(new Alert("warn", "Касса не принята: " + plural(waiting.size(), "рейс", "рейса", "рейсов"),
                        waiting.stream().map(t -> t.getExpeditor().getName()).collect(Collectors.joining(", ")), "Принять", "/admin/cash"));
            List<Receipt> rl = of(receiptList, cid);
            for (Receipt r : rl.stream().filter(r -> r.getStatus() == ReceiptStatus.DRAFT).limit(3).toList())
                out.add(new Alert("info", r.getSource() == ReceiptSource.CRM ? "Приход из CRM ждёт подтверждения" : "Приход ждёт подтверждения",
                        r.getCompany().getName() + " · №" + r.getNumber() + ", " + r.getLines().stream().mapToInt(ReceiptLine::getExpected).sum() + " шт",
                        "Принять", "/admin/stock/receipts/" + r.getId()));
            for (Receipt r : rl) {
                if (r.getStatus() != ReceiptStatus.CONFIRMED || r.getDate() == null || r.getDate().isBefore(today.minusDays(2))) continue;
                List<String> diff = r.getLines().stream().filter(l -> l.getActual() != null && l.getActual() != l.getExpected())
                        .map(l -> (l.getActual() > l.getExpected() ? "+" : "−") + Math.abs(l.getActual() - l.getExpected()) + " шт " + l.getProduct().getName())
                        .toList();
                if (!diff.isEmpty())
                    out.add(new Alert("warn", "Расхождение по приходу №" + r.getNumber(), r.getCompany().getName() + " · "
                            + String.join(", ", diff.subList(0, Math.min(2, diff.size()))) + (diff.size() > 2 ? " и ещё " + (diff.size() - 2) : "")
                            + (r.getCrmOrderId() != null ? " · CRM видит" : ""), "Открыть", "/admin/stock/receipts/" + r.getId()));
            }
            List<Employee> lost = of(people, cid).stream().filter(a -> a.getRole() == Role.AGENT && a.isActive() && a.isStale()).toList();
            if (lost.size() > 2)
                out.add(new Alert("bad", plural(lost.size(), "торговый", "торговых", "торговых") + " не на связи больше суток",
                        lost.stream().map(Employee::getName).collect(Collectors.joining(", ")), "Сотрудники", "/admin/staff"));
            else for (Employee a : lost)
                out.add(new Alert("bad", a.getName() + " не на связи " + hoursSince(a.getLastSync()) + " ч",
                        a.getCompany().getName() + " · последняя связь " + whenText(a.getLastSync()),
                        a.getPhone() != null ? "Позвонить" : "Открыть", a.getPhone() != null ? "tel:" + a.getPhone() : "/admin/staff"));
            List<StaleOutlet> stale = staleOutlets(cid);
            if (!stale.isEmpty()) {
                Map<String, Long> by = stale.stream().collect(Collectors.groupingBy(x -> cid == null ? x.outlet().getCompany().getName()
                        : x.outlet().getAgent() == null ? "без торгового" : x.outlet().getAgent().getName(), LinkedHashMap::new, Collectors.counting()));
                out.add(new Alert("info", plural(stale.size(), "магазин", "магазина", "магазинов") + " без визита " + AssignService.STALE_DAYS + "+ дней",
                        by.entrySet().stream().sorted(Map.Entry.<String, Long>comparingByValue().reversed()).limit(3)
                                .map(e -> e.getKey() + " — " + e.getValue()).collect(Collectors.joining(", ")),
                        "Показать", "/admin/assign"));
            }
            return out;
        }

        /** Действующие магазины без визита STALE_DAYS+ дней (новые — со дня заведения), самые давние первыми. */
        public List<StaleOutlet> staleOutlets(Long cid) {
            if (lastVisit == null) {
                lastVisit = new HashMap<>();
                jdbc.query("select outlet_id, max(started_at) from visits group by outlet_id",
                        rs -> {
                            lastVisit.put(rs.getLong(1), rs.getTimestamp(2).toLocalDateTime().toLocalDate());
                        });
            }
            List<StaleOutlet> out = new ArrayList<>();
            for (Outlet o : of(outletList, cid)) {
                if (o.getStatus() != OutletStatus.ACTIVE) continue;
                LocalDate since = lastVisit.getOrDefault(o.getId(), o.getCreatedAt());
                int days = since == null ? 0 : (int) ChronoUnit.DAYS.between(since, today);
                if (days >= AssignService.STALE_DAYS) out.add(new StaleOutlet(o, days));
            }
            out.sort(Comparator.comparingInt(StaleOutlet::days).reversed());
            return out;
        }

        /** «закончил 17:20», «в работе · 17:31», «нет связи 26 ч»; ждущие сети записи — через точку. */
        private String link(Employee a) {
            if (dayEvents == null) {
                dayEvents = new HashMap<>();
                jdbc.query("select user_id, kind, max(event_at) from app_events where event_at >= ? and kind in ('DAY_START', 'DAY_END')"
                        + " group by user_id, kind", rs -> {
                    dayEvents.put(rs.getLong(1) + rs.getString(2), rs.getTimestamp(3).toLocalDateTime());
                }, today.atStartOfDay());
            }
            String text;
            LocalDateTime start = dayEvents.get(a.getId() + "DAY_START"), end = dayEvents.get(a.getId() + "DAY_END");
            if (a.getLastSync() == null) text = "ещё не входил";
            else if (a.isStale()) text = "нет связи " + hoursSince(a.getLastSync()) + " ч";
            else if (end != null && (start == null || !end.isBefore(start))) text = "закончил " + end.format(HM);
            else if (!a.getLastSync().toLocalDate().isBefore(today)) text = "в работе · " + a.getLastSync().format(HM);
            else text = "сегодня не выходил";
            return a.getUnsent() > 0 ? text + " · " + plural(a.getUnsent(), "запись ждёт", "записи ждут", "записей ждут") + " сети" : text;
        }

        private int hoursSince(LocalDateTime t) {
            return (int) ChronoUnit.HOURS.between(t, LocalDateTime.now(clock));
        }

        private String whenText(LocalDateTime t) {
            LocalDate d = t.toLocalDate();
            String day = d.equals(today) ? "сегодня" : d.equals(today.minusDays(1)) ? "вчера" : d.format(DM);
            return day + " " + t.format(HM);
        }

        public List<CompanyRow> companyRows() {
            Map<Long, Long> outletsBy = outletList.stream().collect(Collectors.groupingBy(Outlet::getCompanyId, Collectors.counting()));
            return companies.all().stream().map(c -> new CompanyRow(c, summary(c.getId()),
                    (int) people.stream().filter(e -> c.getId().equals(e.getCompanyId()) && e.getRole() == Role.AGENT).count(),
                    (int) people.stream().filter(e -> c.getId().equals(e.getCompanyId()) && e.getRole() == Role.EXPEDITOR).count(),
                    outletsBy.getOrDefault(c.getId(), 0L).intValue())).toList();
        }

        public List<QualityRow> quality(Long cid) {
            return DashboardService.quality(returns.findAll(), cid);
        }
    }

    private static String money(long v) {
        return String.format(Locale.ROOT, "%,d", v).replace(',', ' ') + " ₸";
    }

    private static String plural(long n, String one, String few, String many) {
        long m10 = n % 10, m100 = n % 100;
        String w = m10 == 1 && m100 != 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? few : many;
        return n + " " + w;
    }

    private static String dot(String... parts) {
        return Arrays.stream(parts).filter(Objects::nonNull).collect(Collectors.joining(" · "));
    }
}
