package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
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
    private final Clock clock;

    /** Главные цифры для дашборда и блока в CRM. */
    public record Summary(long deliveredToday, int deliveredStops, long tomorrowSum, int tomorrowOrders,
                          long cashOnHands, int openTrips, long debts, long overdue, long returnsToday,
                          int returnsQty, int needsApproval, int pendingOutlets) {
        /** Возвраты в процентах от выданного за день, «7,5». */
        public String returnsPercent() {
            double v = deliveredToday == 0 ? 0 : returnsToday * 100.0 / deliveredToday;
            return String.format(Locale.forLanguageTag("ru"), "%.1f", v);
        }
    }

    public record AgentRow(Employee agent, int orders, long sum, int refusals) {
        public boolean stale() {
            return agent.isStale();
        }
    }

    /** Что требует внимания: tone — warn / info / bad, ссылка на раздел. */
    public record Alert(String tone, String text, String value, String href) {
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
        private final List<Order> upcoming = orders.findByDeliveryDateGreaterThanEqual(today);
        private final List<Order> createdToday = orders.findByCreatedAtGreaterThanEqualAndCreatedAtLessThan(
                today.atStartOfDay(), today.plusDays(1).atStartOfDay());
        private final List<Trip> tripList = trips.current(null);
        private final List<ProductReturn> returnsToday = returns.findByDate(today);
        private final List<Outlet> outletList = outlets.list(null);
        private final List<Receipt> receiptList = receipts.findAllByOrderByDateDescIdDesc();
        private final List<Visit> visitsToday = visits.findByStartedAtGreaterThanEqualAndStartedAtLessThan(
                today.atStartOfDay(), today.plusDays(1).atStartOfDay());
        private final List<Employee> people = staff.employees(null);

        private <T extends CompanyEntity> List<T> of(List<T> list, Long cid) {
            return cid == null ? list : list.stream().filter(x -> cid.equals(x.getCompanyId())).toList();
        }

        public List<Trip> trips(Long cid) {
            return of(tripList, cid);
        }

        public Summary summary(Long cid) {
            List<Order> os = of(upcoming, cid);
            List<Order> delivered = os.stream().filter(o -> today.equals(o.getDeliveryDate()) && o.getStatus().delivered()).toList();
            List<Order> tomorrow = os.stream().filter(o -> o.getDeliveryDate().isAfter(today) && o.getStatus() != OrderStatus.CANCELLED).toList();
            List<Trip> open = of(tripList, cid).stream().filter(t -> t.getStatus().cashOnHands()).toList();
            List<ProductReturn> rs = of(returnsToday, cid);
            List<Outlet> ol = of(outletList, cid);
            return new Summary(
                    delivered.stream().mapToLong(Order::getDeliveredTotal).sum(), delivered.size(),
                    tomorrow.stream().mapToLong(Order::getTotal).sum(), tomorrow.size(),
                    open.stream().mapToLong(Trip::getCash).sum(), open.size(),
                    ol.stream().mapToLong(o -> Math.max(0, o.getDebt())).sum(), ol.stream().mapToLong(Outlet::getOverdue).sum(),
                    rs.stream().mapToLong(ProductReturn::getTotal).sum(), rs.stream().mapToInt(ProductReturn::getQty).sum(),
                    (int) os.stream().filter(o -> o.getStatus() == OrderStatus.NEEDS_APPROVAL).count(),
                    (int) ol.stream().filter(o -> o.getStatus() == OutletStatus.PENDING).count());
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
                out.add(new AgentRow(a, taken.size(), taken.stream().mapToLong(Order::getTotal).sum(), refusals));
            }
            out.sort(Comparator.comparingLong(AgentRow::sum).reversed());
            return out;
        }

        public List<Alert> alerts(Long cid) {
            List<Alert> out = new ArrayList<>();
            Summary s = summary(cid);
            if (s.needsApproval() > 0)
                out.add(new Alert("warn", "Заказы ждут разрешения: долг сверх лимита", String.valueOf(s.needsApproval()), "/admin/approvals"));
            if (s.pendingOutlets() > 0)
                out.add(new Alert("info", "Новые магазины на проверке", String.valueOf(s.pendingOutlets()), "/admin/outlets?status=PENDING"));
            long waiting = of(tripList, cid).stream().filter(Trip::isWaitingCash).count();
            if (waiting > 0)
                out.add(new Alert("warn", "Рейсы пройдены, касса не принята", String.valueOf(waiting), "/admin/cash"));
            long drafts = of(receiptList, cid).stream().filter(r -> r.getStatus() == ReceiptStatus.DRAFT).count();
            if (drafts > 0)
                out.add(new Alert("info", "Приходы из CRM ждут подтверждения", String.valueOf(drafts), "/admin/stock?tab=receipts"));
            for (Trip t : of(tripList, cid)) {
                Long d = t.getCashDiff();
                if (d != null && -d > settings.of(t.getCompanyId()).getCashTolerance())
                    out.add(new Alert("bad", "Недостача по рейсу: " + t.getExpeditor().getName(), "−" + money(-d), "/admin/cash/" + t.getId()));
            }
            for (Employee a : of(people, cid)) {
                if (a.getRole() == Role.AGENT && a.isStale())
                    out.add(new Alert("bad", "Агент давно не синхронизировался: " + a.getName(), "> 24 ч", "/admin/staff"));
            }
            if (s.overdue() > 0)
                out.add(new Alert("bad", "Просроченные долги магазинов", money(s.overdue()), "/admin/debts?overdue=1"));
            return out;
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
}
