package com.confectionery.distribution.stub;

import com.confectionery.distribution.domain.*;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * ЗАГЛУШКА: все данные админки живут в памяти и пересоздаются при каждом запуске. Числа случайные,
 * но связаны между собой (рейс состоит из заказов, касса — из оплат по точкам), поэтому сводки на
 * разных страницах сходятся. На этапе 1 этот класс заменяется репозиториями JPA, страницы остаются.
 *
 * <p>companyId = null везде означает «все компании» (режим владельца).
 */
@Component
public class StubStore {

    private final Random rnd = new Random(42);
    private final LocalDate today = LocalDate.now();
    private final LocalDateTime now = LocalDateTime.now();
    private long seq = 1;

    private final List<Company> companies = new ArrayList<>();
    private final List<Region> regions = new ArrayList<>();
    private final List<Route> routes = new ArrayList<>();
    private final List<Employee> employees = new ArrayList<>();
    private final List<Vehicle> vehicles = new ArrayList<>();
    private final List<Outlet> outlets = new ArrayList<>();
    private final List<Product> products = new ArrayList<>();
    private final List<Order> orders = new ArrayList<>();
    private final List<Trip> trips = new ArrayList<>();
    private final List<Payment> payments = new ArrayList<>();
    private final List<ProductReturn> returns = new ArrayList<>();
    private final List<Receipt> receipts = new ArrayList<>();
    /** Остатки: товар → [основной склад, склад негодного]. */
    private final Map<Product, int[]> stock = new LinkedHashMap<>();
    private final Employee owner;

    public StubStore() {
        owner = new Employee().setId(seq++).setName("Владелец").setRole(Role.SUPER_ADMIN).setPhone("+7 700 000 00 00");
        employees.add(owner);
        build();
    }

    // ------------------------------------------------------------------ чтение

    public LocalDate today() {
        return today;
    }

    public Employee owner() {
        return owner;
    }

    public List<Company> companies() {
        return companies;
    }

    public Company company(Long id) {
        return id == null ? null : find(companies, id, Company::getId);
    }

    public List<Region> regions(Long cid) {
        return scope(regions, cid, Region::getCompany);
    }

    public List<Route> routes(Long cid) {
        return scope(routes, cid, Route::getCompany);
    }

    public List<Employee> employees(Long cid) {
        return employees.stream().filter(e -> e.getCompany() != null)
                .filter(e -> cid == null || e.getCompany().getId().equals(cid)).toList();
    }

    public List<Employee> staff(Long cid, Role role) {
        return employees(cid).stream().filter(e -> e.getRole() == role).toList();
    }

    /** Первый сотрудник компании с ролью — для «кто вошёл» в режиме просмотра под ролью. */
    public Employee firstWithRole(Long cid, Role role) {
        if (role == Role.SUPER_ADMIN) return owner;
        Long id = cid != null ? cid : companies.get(0).getId();
        return staff(id, role).stream().findFirst().orElse(owner);
    }

    public List<Vehicle> vehicles(Long cid) {
        return scope(vehicles, cid, Vehicle::getCompany);
    }

    public List<Outlet> outlets(Long cid) {
        return scope(outlets, cid, Outlet::getCompany);
    }

    public Outlet outlet(Long id) {
        return find(outlets, id, Outlet::getId);
    }

    public List<Product> products(Long cid) {
        // в режиме «все компании» каталог показываем по первой компании: у каждой свой прайс
        return scope(products, cid != null ? cid : companies.get(0).getId(), Product::getCompany);
    }

    public List<Order> orders(Long cid) {
        return scope(orders, cid, Order::getCompany);
    }

    public Order order(Long id) {
        return find(orders, id, Order::getId);
    }

    public List<Order> ordersOf(Outlet o) {
        return orders.stream().filter(x -> x.getOutlet() == o)
                .sorted(Comparator.comparing(Order::getCreatedAt).reversed()).toList();
    }

    public List<Trip> trips(Long cid) {
        return scope(trips, cid, Trip::getCompany);
    }

    public Trip trip(Long id) {
        return find(trips, id, Trip::getId);
    }

    public List<Payment> paymentsOf(Outlet o) {
        return payments.stream().filter(p -> p.getOutlet() == o).toList();
    }

    public List<ProductReturn> returns(Long cid) {
        return scope(returns, cid, ProductReturn::getCompany);
    }

    public List<ProductReturn> returnsOf(Outlet o) {
        return returns.stream().filter(r -> r.getOutlet() == o).toList();
    }

    public List<Receipt> receipts(Long cid) {
        return scope(receipts, cid, Receipt::getCompany).stream()
                .sorted(Comparator.comparing(Receipt::getDate).reversed()).toList();
    }

    public Receipt receipt(Long id) {
        return find(receipts, id, Receipt::getId);
    }

    /** Строка склада: товар, основной склад, в машинах, в резерве под заказы на завтра, негодный. */
    public record StockRow(Product product, int main, int inVehicles, int reserved, int defect) {
        public int free() {
            return main - reserved;
        }

        public boolean low() {
            return free() < product.getPerBox() * 2;
        }
    }

    public List<StockRow> stock(Long cid) {
        List<StockRow> out = new ArrayList<>();
        for (Product p : products(cid)) {
            int[] s = stock.getOrDefault(p, new int[2]);
            out.add(new StockRow(p, s[0], qtyIn(p, OrderStatus.IN_TRIP), qtyReserved(p), s[1]));
        }
        return out;
    }

    private int qtyIn(Product p, OrderStatus st) {
        return orders.stream().filter(o -> o.getStatus() == st).flatMap(o -> o.getLines().stream())
                .filter(l -> l.getProduct() == p).mapToInt(OrderLine::getQty).sum();
    }

    private int qtyReserved(Product p) {
        return orders.stream().filter(o -> o.getStatus().cancellable()).flatMap(o -> o.getLines().stream())
                .filter(l -> l.getProduct() == p).mapToInt(OrderLine::getQty).sum();
    }

    /** Лист сборки: товар → штук по всем заказам рейса (или заказам на дату). */
    public record PickRow(Product product, int qty, int boxes, int pieces) {
    }

    public List<PickRow> pickList(List<Order> list) {
        Map<Product, Integer> m = new LinkedHashMap<>();
        for (Order o : list) for (OrderLine l : o.getLines()) m.merge(l.getProduct(), l.getQty(), Integer::sum);
        return m.entrySet().stream()
                .sorted(Comparator.comparing(e -> e.getKey().getName()))
                .map(e -> {
                    int per = Math.max(1, e.getKey().getPerBox());
                    return new PickRow(e.getKey(), e.getValue(), e.getValue() / per, e.getValue() % per);
                }).toList();
    }

    // ------------------------------------------------------------------ сводки

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

    public Summary summary(Long cid) {
        List<Order> os = orders(cid);
        List<Order> delivered = os.stream().filter(o -> today.equals(o.getDeliveryDate()) && o.getStatus().delivered()).toList();
        List<Order> tomorrow = os.stream().filter(o -> o.getDeliveryDate().isAfter(today) && o.getStatus() != OrderStatus.CANCELLED).toList();
        List<Trip> ts = trips(cid);
        List<ProductReturn> rs = returns(cid).stream().filter(r -> today.equals(r.getDate())).toList();
        List<Outlet> ol = outlets(cid);
        return new Summary(
                delivered.stream().mapToLong(Order::getDeliveredTotal).sum(), delivered.size(),
                tomorrow.stream().mapToLong(Order::getTotal).sum(), tomorrow.size(),
                ts.stream().filter(t -> t.getStatus().cashOnHands()).mapToLong(Trip::getCash).sum(),
                (int) ts.stream().filter(t -> t.getStatus().cashOnHands()).count(),
                ol.stream().mapToLong(Outlet::getDebt).sum(), ol.stream().mapToLong(Outlet::getOverdue).sum(),
                rs.stream().mapToLong(ProductReturn::getTotal).sum(), rs.stream().mapToInt(ProductReturn::getQty).sum(),
                (int) os.stream().filter(o -> o.getStatus() == OrderStatus.NEEDS_APPROVAL).count(),
                (int) ol.stream().filter(o -> o.getStatus() == OutletStatus.PENDING).count());
    }

    public record AgentRow(Employee agent, int orders, long sum, int refusals) {
        public boolean stale() {
            return agent.getLastSync() != null && agent.getLastSync().isBefore(LocalDateTime.now().minusHours(24));
        }
    }

    public List<AgentRow> agentsToday(Long cid) {
        List<AgentRow> out = new ArrayList<>();
        for (Employee a : staff(cid, Role.AGENT)) {
            List<Order> taken = orders.stream().filter(o -> o.getAgent() == a && today.equals(o.getCreatedAt().toLocalDate())).toList();
            out.add(new AgentRow(a, taken.size(), taken.stream().mapToLong(Order::getTotal).sum(),
                    Math.max(0, a.getVisitedToday() - taken.size())));
        }
        out.sort(Comparator.comparingLong(AgentRow::sum).reversed());
        return out;
    }

    /** Что требует внимания: tone — warn / info / bad, ссылка на раздел. */
    public record Alert(String tone, String text, String value, String href) {
    }

    public List<Alert> alerts(Long cid) {
        List<Alert> out = new ArrayList<>();
        Summary s = summary(cid);
        if (s.needsApproval() > 0)
            out.add(new Alert("warn", "Заказы ждут разрешения: долг сверх лимита", String.valueOf(s.needsApproval()), "/admin/orders?status=NEEDS_APPROVAL"));
        if (s.pendingOutlets() > 0)
            out.add(new Alert("info", "Новые магазины на проверке", String.valueOf(s.pendingOutlets()), "/admin/outlets?status=PENDING"));
        long returned = trips(cid).stream().filter(t -> t.getStatus() == TripStatus.RETURNED).count();
        if (returned > 0)
            out.add(new Alert("warn", "Рейсы вернулись, касса не принята", String.valueOf(returned), "/admin/cash"));
        long drafts = receipts(cid).stream().filter(r -> r.getStatus() == ReceiptStatus.DRAFT).count();
        if (drafts > 0)
            out.add(new Alert("info", "Приходы из CRM ждут подтверждения", String.valueOf(drafts), "/admin/stock?tab=receipts"));
        for (Trip t : trips(cid)) {
            Long d = t.getCashDiff();
            if (d != null && d < 0)
                out.add(new Alert("bad", "Недостача по рейсу: " + t.getExpeditor().getName(), "−" + money(Math.abs(d)), "/admin/cash/" + t.getId()));
        }
        for (AgentRow r : agentsToday(cid)) {
            if (r.stale())
                out.add(new Alert("bad", "Агент давно не синхронизировался: " + r.agent().getName(), "> 24 ч", "/admin/staff"));
        }
        if (s.overdue() > 0)
            out.add(new Alert("bad", "Просроченные долги магазинов", money(s.overdue()), "/admin/debts?overdue=1"));
        return out;
    }

    public record CompanyRow(Company company, Summary summary, int agents, int expeditors, int outlets, int routes) {
    }

    public List<CompanyRow> companyRows() {
        return companies.stream().map(c -> new CompanyRow(c, summary(c.getId()),
                staff(c.getId(), Role.AGENT).size(), staff(c.getId(), Role.EXPEDITOR).size(),
                outlets(c.getId()).size(), routes(c.getId()).size())).toList();
    }

    /** Возвраты негодного по товарам (для отчёта о качестве). */
    public record QualityRow(String product, String reason, int qty, long sum) {
    }

    public List<QualityRow> quality(Long cid) {
        Map<String, QualityRow> m = new LinkedHashMap<>();
        for (ProductReturn r : returns(cid)) {
            for (ReturnLine l : r.getLines()) {
                String k = l.getProduct().getName() + "|" + l.getReason().getLabel();
                QualityRow q = m.get(k);
                m.put(k, new QualityRow(l.getProduct().getName(), l.getReason().getLabel(),
                        (q == null ? 0 : q.qty()) + l.getQty(), (q == null ? 0 : q.sum()) + l.getSum()));
            }
        }
        return m.values().stream().sorted(Comparator.comparingInt(QualityRow::qty).reversed()).toList();
    }

    // ------------------------------------------------------------------ действия (меняют данные в памяти)

    public synchronized void approveOrder(Long id, String who) {
        Order o = order(id);
        if (o != null && o.getStatus() == OrderStatus.NEEDS_APPROVAL) {
            o.setStatus(OrderStatus.ACCEPTED);
            o.event(LocalDateTime.now(), who, "Разрешил заказ сверх лимита долга");
        }
    }

    public synchronized void cancelOrder(Long id, String who, String reason) {
        Order o = order(id);
        if (o != null && o.getStatus().cancellable()) {
            o.setStatus(OrderStatus.CANCELLED);
            o.event(LocalDateTime.now(), who, "Отменил: " + reason);
        }
    }

    public synchronized void approveOutlet(Long id) {
        Outlet o = outlet(id);
        if (o != null && o.getStatus() == OutletStatus.PENDING) o.setStatus(OutletStatus.ACTIVE);
    }

    public synchronized void acceptTrip(Long id, long counted, boolean kaspi, boolean goods, String who) {
        Trip t = trip(id);
        if (t == null || t.getStatus() != TripStatus.RETURNED) return;
        t.setCashCounted(counted).setKaspiChecked(kaspi).setGoodsChecked(goods);
        if (kaspi && goods) {
            t.setStatus(TripStatus.CLOSED).setClosedAt(LocalDateTime.now()).setAcceptedBy(who);
        }
    }

    public synchronized void confirmReceipt(Long id, Map<Long, Integer> actual, String who) {
        Receipt r = receipt(id);
        if (r == null || r.getStatus() != ReceiptStatus.DRAFT) return;
        for (ReceiptLine l : r.getLines()) {
            int q = actual.getOrDefault(l.getProduct().getId(), l.getExpected());
            l.setActual(q);
            stock.computeIfAbsent(l.getProduct(), k -> new int[2])[0] += q;
        }
        r.setStatus(ReceiptStatus.CONFIRMED).setConfirmedBy(who);
    }

    // ------------------------------------------------------------------ генерация заглушек

    private static final String[] SHOPS = {"Асель", "Береке", "Дос-Маркет", "Нур", "Жулдыз", "Самал", "Айгуль",
            "Мерей", "Алтын", "Шанырак", "Ак Жол", "Улан", "Достык", "Арман", "Сая", "Камила", "Мирас", "Тумар",
            "Аружан", "Нурлы", "Сункар", "Асем", "Баян", "Сапа", "Ырыс", "Кайнар", "Ажар", "Орда", "Дана", "Томирис",
            "Бахыт", "Алма", "Жанар", "Ару", "Мадина", "Сымбат", "Ерке", "Гульдер", "Айдана", "Карлыгаш", "Ботагоз",
            "Даулет", "Нурай", "Акбота", "Жаркын", "Самгау", "Кулагер", "Байтерек", "Мейрам", "Береке-2"};
    private static final String[] STREETS = {"ул. Абая", "ул. Толе би", "ул. Байтурсынова", "ул. Жибек жолы",
            "пр. Республики", "ул. Momyshuly", "ул. Казыбек би", "ул. Сейфуллина", "мкр. Нурсат", "мкр. Самал",
            "ул. Кунаева", "ул. Аль-Фараби", "ул. Туркестанская", "ул. Желтоксан"};
    private static final String[] OWNERS = {"Нурлан А.", "Гульмира С.", "Ерлан Б.", "Айжан К.", "Бакыт Т.",
            "Сауле М.", "Арман Ж.", "Динара Е.", "Кайрат О.", "Жанна Н.", "Марат С.", "Алия Р."};

    private void build() {
        Company c1 = company("Своя доставка", "Даурен Абдиев", null, true);
        Company c2 = company("Склад-дилер А", "Серик Жумабаев", "ТОО «Дилер А»", false);
        Company c3 = company("Склад-дилер Б", "Гульнара Ахметова", "ИП «Дилер Б»", false);

        staff(c1, "Даурен Абдиев", "Сауле Ким", "Ерболат Нуров");
        staff(c2, "Серик Жумабаев", "Динара Оспанова", "Талгат Беков");
        staff(c3, "Гульнара Ахметова", "Жанна Серикова", "Канат Алиев");

        catalog(c1, 100);
        catalog(c2, 103);
        catalog(c3, 105);

        int shop = 0;
        shop = network(c1, new String[]{"Центр", "Север"}, new String[]{"Ержан Т.", "Дамир Н.", "Аскар Б.", "Мадина С."}, shop);
        shop = network(c2, new String[]{"Восток", "Пригород"}, new String[]{"Айгерим К.", "Бауыржан С.", "Нурсултан Е."}, shop);
        network(c3, new String[]{"Запад"}, new String[]{"Тимур Ж.", "Алия М.", "Руслан К."}, shop);

        expeditors(c1, new String[]{"Азамат К.", "Серик Д."}, new String[]{"245 AKS 02", "318 BDK 02"}, "Hyundai Porter");
        expeditors(c2, new String[]{"Ерлан О.", "Жандос П."}, new String[]{"507 ACE 13", "740 KAZ 13"}, "ГАЗель Next");
        expeditors(c3, new String[]{"Марат И."}, new String[]{"112 KZA 13"}, "Kia Bongo");

        for (Company c : companies) {
            initialStock(c);
            ordersAndTrips(c);
            receiptsFor(c);
        }
        // один агент давно не выходил на связь — для блока «Требует внимания»
        employees.stream().filter(e -> "Бауыржан С.".equals(e.getName())).findFirst()
                .ifPresent(e -> e.setLastSync(now.minusHours(26)).setUnsent(0));
        employees.stream().filter(e -> "Ержан Т.".equals(e.getName())).findFirst()
                .ifPresent(e -> e.setUnsent(3));
    }

    private Company company(String name, String director, String crmClient, boolean own) {
        Company c = new Company().setId(seq++).setName(name).setDirector(director).setCrmClient(crmClient).setOwn(own)
                .setPhone("+7 700 000 0" + (companies.size() + 1) + " 00");
        companies.add(c);
        return c;
    }

    private Employee person(Company c, String name, Role role) {
        Employee e = new Employee().setId(seq++).setCompany(c).setName(name).setRole(role)
                .setPhone("+7 701 000 " + String.format("%02d %02d", c.getId(), employees.size()));
        employees.add(e);
        return e;
    }

    private void staff(Company c, String director, String operator, String storekeeper) {
        person(c, director, Role.DIRECTOR);
        person(c, operator, Role.OPERATOR);
        person(c, storekeeper, Role.STOREKEEPER);
    }

    private void catalog(Company c, int pricePercent) {
        Object[][] items = {
                {"Печенье овсяное, 400 г", "Печенье", 12, 620, 750, "ЮС-0101"},
                {"Печенье сахарное, 350 г", "Печенье", 12, 540, 650, "ЮС-0102"},
                {"Пряники медовые, 300 г", "Печенье", 16, 480, 590, "ЮС-0105"},
                {"Торт «Медовик», 1 кг", "Торты", 4, 3600, 4300, "ЮС-0301"},
                {"Торт «Наполеон», 1 кг", "Торты", 4, 3900, 4600, "ЮС-0302"},
                {"Рулет бисквитный, 300 г", "Рулеты", 12, 780, 950, "ЮС-0401"},
                {"Рулет с маком, 350 г", "Рулеты", 12, 860, 1040, "ЮС-0402"},
                {"Кекс «Столичный», 500 г", "Кексы", 10, 1220, 1450, "ЮС-0501"},
                {"Кекс с изюмом, 300 г", "Кексы", 12, 760, 920, "ЮС-0502"},
                {"Пирожное «Картошка», 6 шт", "Пирожные", 8, 1150, 1390, "ЮС-0601"},
                {"Вафли «Сливочные», 250 г", "Вафли", 20, 540, 650, null},
                {"Зефир ванильный, 300 г", "Зефир", 12, 690, 840, null},
        };
        int n = 0;
        for (Object[] it : items) {
            long whole = round10((int) it[3] * pricePercent / 100);
            long retail = round10((int) it[4] * pricePercent / 100);
            Product p = new Product().setId(seq++).setCompany(c).setName((String) it[0]).setCategory((String) it[1])
                    .setPerBox((int) it[2]).setWholesale(whole).setRetail(retail).setCrmCode((String) it[5])
                    .setBarcode("487000" + String.format("%07d", 1000 + n++));
            products.add(p);
        }
    }

    private static long round10(long v) {
        return Math.round(v / 10.0) * 10;
    }

    private int network(Company c, String[] regionNames, String[] agentNames, int shop) {
        List<Region> rs = new ArrayList<>();
        for (String rn : regionNames) {
            Region r = new Region().setId(seq++).setCompany(c).setName(rn);
            regions.add(r);
            rs.add(r);
        }
        String[][] days = {{"Пн, Чт", "Вт, Пт"}, {"Ср, Сб", "Пн, Чт"}, {"Вт, Пт", "Ср, Сб"}};
        int[] routeNo = new int[rs.size()];
        for (int i = 0; i < agentNames.length; i++) {
            Employee a = person(c, agentNames[i], Role.AGENT);
            a.setLastSync(now.minusMinutes(5 + rnd.nextInt(80)));
            Region r = rs.get(i % rs.size());
            for (int k = 0; k < 2; k++) {
                Route route = new Route().setId(seq++).setCompany(c).setRegion(r).setAgent(a)
                        .setName(r.getName() + "-" + (++routeNo[i % rs.size()])).setDays(days[i % days.length][k]);
                routes.add(route);
                r.getRoutes().add(route);
                int count = 5 + rnd.nextInt(3);
                for (int j = 0; j < count; j++) {
                    route.getOutlets().add(outlet(c, route, shop++));
                }
            }
            Route todays = routes.stream().filter(x -> x.getAgent() == a).findFirst().orElseThrow();
            int plan = todays.getOutlets().size() + 8 + rnd.nextInt(6);
            a.setPlanToday(plan).setVisitedToday(Math.max(3, plan - 4 - rnd.nextInt(9)));
        }
        return shop;
    }

    private Outlet outlet(Company c, Route route, int n) {
        String name = n < SHOPS.length ? "Магазин «" + SHOPS[n] + "»" : "Магазин №" + (n + 1);
        boolean retail = rnd.nextInt(5) == 0;
        long limit = retail ? 50_000 : (rnd.nextBoolean() ? 100_000 : 150_000);
        long debt = rnd.nextInt(10) < 4 ? 0 : (5_000 + rnd.nextInt(130) * 1_000L);
        long overdue = debt > 20_000 && rnd.nextInt(6) == 0 ? (debt / 3 / 1000) * 1000 : 0;
        Outlet o = new Outlet().setId(seq++).setCompany(c).setRoute(route).setName(name)
                .setLegal((rnd.nextInt(4) == 0 ? "ТОО «" : "ИП «") + (n < SHOPS.length ? SHOPS[n] : "№" + (n + 1)) + "»")
                .setBin("[БИН]").setOwner(OWNERS[n % OWNERS.length])
                .setPhone("+7 7" + (n % 3 == 0 ? "01" : n % 3 == 1 ? "05" : "47") + " 000 " + String.format("%02d %02d", n / 100, n % 100))
                .setAddress(STREETS[n % STREETS.length] + ", " + (3 + rnd.nextInt(140)))
                .setPriceType(retail ? "Розница" : "Опт").setCreditLimit(limit).setDebt(debt).setOverdue(overdue)
                .setPaymentDays(retail ? 3 : 7).setCreatedAt(today.minusDays(30 + rnd.nextInt(400))).setCreatedBy("импорт Doctor Sales");
        if (debt > 0) {
            o.setLastPaymentDate(today.minusDays(1 + rnd.nextInt(12))).setLastPaymentSum((10 + rnd.nextInt(40)) * 1000L);
        }
        if (n % 23 == 7) {
            o.setStatus(OutletStatus.PENDING).setCreatedAt(today).setCreatedBy(route.getAgent().getName())
                    .setDebt(0).setOverdue(0).setLastPaymentDate(null).setBin("—");
        } else if (n % 37 == 11) {
            o.setStatus(OutletStatus.CLOSED).setDebt(0).setOverdue(0);
        }
        outlets.add(o);
        return o;
    }

    private void expeditors(Company c, String[] names, String[] plates, String model) {
        for (int i = 0; i < names.length; i++) {
            Employee e = person(c, names[i], Role.EXPEDITOR);
            e.setLastSync(now.minusMinutes(3 + rnd.nextInt(40)));
            Vehicle v = new Vehicle().setId(seq++).setCompany(c).setPlate(plates[i]).setModel(model).setExpeditor(e);
            vehicles.add(v);
            e.setVehicle(v);
        }
    }

    private void initialStock(Company c) {
        for (Product p : products(c.getId())) {
            stock.put(p, new int[]{p.getPerBox() * (6 + rnd.nextInt(30)), rnd.nextInt(8)});
        }
    }

    private Order newOrder(Company c, Outlet o, Employee agent, LocalDateTime created, LocalDate delivery, String prefix) {
        List<Product> cat = products(c.getId());
        Order order = new Order().setId(seq++).setNumber(prefix + "-" + (1000 + seq)).setCompany(c).setOutlet(o)
                .setAgent(agent).setCreatedAt(created).setDeliveryDate(delivery).setStatus(OrderStatus.ACCEPTED);
        int lines = 2 + rnd.nextInt(4);
        Set<Product> used = new HashSet<>();
        for (int i = 0; i < lines; i++) {
            Product p = cat.get(rnd.nextInt(cat.size()));
            if (!used.add(p)) continue;
            int qty = p.getPerBox() <= 4 ? 1 + rnd.nextInt(4) : p.getPerBox() * (1 + rnd.nextInt(2)) / (rnd.nextBoolean() ? 1 : 2);
            order.getLines().add(new OrderLine().setProduct(p).setQty(qty).setPrice(p.price(o.getPriceType())));
        }
        int pm = rnd.nextInt(10);
        order.setPayment(pm < 6 ? PaymentMethod.CASH : pm < 8 ? PaymentMethod.KASPI : PaymentMethod.CREDIT);
        order.event(created, agent.getName(), "Оформил заказ в магазине (с телефона)");
        orders.add(order);
        return order;
    }

    private void ordersAndTrips(Company c) {
        String prefix = new String[]{"С", "А", "Б", "Г", "Д"}[companies.indexOf(c) % 5];
        List<Employee> agents = staff(c.getId(), Role.AGENT);
        List<Order> forToday = new ArrayList<>();

        for (Employee a : agents) {
            List<Route> rs = routes.stream().filter(r -> r.getAgent() == a).toList();
            // вчерашние заказы (второй маршрут агента) — сегодня их развозят экспедиторы
            for (Outlet o : rs.get(1).getOutlets()) {
                if (o.getStatus() != OutletStatus.ACTIVE || rnd.nextInt(10) < 3) continue;
                LocalDateTime created = today.minusDays(1).atTime(9 + rnd.nextInt(8), rnd.nextInt(60));
                Order ord = newOrder(c, o, a, created, today, prefix);
                ord.setStatus(OrderStatus.IN_TRIP);
                ord.event(today.atTime(7, 40), "Склад", "Собран и загружен в машину");
                forToday.add(ord);
            }
            // сегодняшние заказы (первый маршрут) — доставка завтра
            int taken = 0;
            for (Outlet o : rs.get(0).getOutlets()) {
                if (o.getStatus() == OutletStatus.CLOSED || rnd.nextInt(10) < 3) continue;
                LocalDateTime created = today.atTime(9, 0).plusMinutes(25L * taken + rnd.nextInt(20));
                if (created.isAfter(now) && taken > 0) continue;
                Order ord = newOrder(c, o, a, created.isAfter(now) ? now.minusMinutes(5) : created, today.plusDays(1), prefix);
                taken++;
                if (ord.getPayment() == PaymentMethod.CREDIT && o.getDebt() + ord.getTotal() > o.getCreditLimit()) {
                    ord.setStatus(OrderStatus.NEEDS_APPROVAL);
                    ord.event(ord.getCreatedAt().plusMinutes(1), "Система",
                            "Долг станет " + money(o.getDebt() + ord.getTotal()) + " при лимите " + money(o.getCreditLimit()) + " — нужно разрешение");
                } else if (rnd.nextInt(5) == 0) {
                    ord.setStatus(OrderStatus.ASSEMBLED);
                    ord.event(now.minusMinutes(20), "Склад", "Собран");
                }
            }
        }
        // хотя бы один заказ сверх лимита долга в каждой компании — чтобы было что разрешать
        if (orders.stream().noneMatch(o -> o.getCompany() == c && o.getStatus() == OrderStatus.NEEDS_APPROVAL)) {
            orders.stream().filter(o -> o.getCompany() == c && o.getStatus() == OrderStatus.ACCEPTED
                    && o.getOutlet().getCreditLimit() > o.getTotal()).findFirst().ifPresent(o -> {
                Outlet out = o.getOutlet();
                out.setDebt(out.getCreditLimit() - o.getTotal() / 2);
                o.setPayment(PaymentMethod.CREDIT).setStatus(OrderStatus.NEEDS_APPROVAL);
                o.event(o.getCreatedAt().plusMinutes(1), "Система", "Долг станет " + money(out.getDebt() + o.getTotal())
                        + " при лимите " + money(out.getCreditLimit()) + " — нужно разрешение");
            });
        }
        // одна отмена — для вида
        orders.stream().filter(o -> o.getCompany() == c && o.getStatus() == OrderStatus.ACCEPTED).findFirst()
                .ifPresent(o -> cancelOrder(o.getId(), "Оператор", "магазин попросил перенести"));

        List<Employee> exps = staff(c.getId(), Role.EXPEDITOR);
        TripStatus[] plan = c.isOwn() ? new TripStatus[]{TripStatus.ON_ROAD, TripStatus.RETURNED}
                : exps.size() > 1 ? new TripStatus[]{TripStatus.ON_ROAD, TripStatus.CLOSED} : new TripStatus[]{TripStatus.ON_ROAD};
        for (int i = 0; i < exps.size(); i++) {
            Employee e = exps.get(i);
            Trip t = new Trip().setId(seq++).setNumber("Р-" + today.getDayOfMonth() + String.format("%02d", seq % 100))
                    .setCompany(c).setDate(today).setExpeditor(e).setVehicle(e.getVehicle()).setStatus(plan[i])
                    .setStartedAt(today.atTime(8, 10 + 10 * i));
            for (int k = i; k < forToday.size(); k += exps.size()) {
                Order o = forToday.get(k);
                t.getOrders().add(o);
                o.setTrip(t);
            }
            trips.add(t);
            int done = plan[i] == TripStatus.ON_ROAD ? t.getOrders().size() * 2 / 5 + 1 : t.getOrders().size();
            LocalDateTime at = today.atTime(9, 0);
            for (int k = 0; k < Math.min(done, t.getOrders().size()); k++) {
                at = at.plusMinutes(18 + rnd.nextInt(15));
                if (at.isAfter(now)) at = now.minusMinutes(t.getOrders().size() - k);
                deliver(t, t.getOrders().get(k), at);
            }
            if (plan[i] == TripStatus.CLOSED) {
                t.setCashCounted(t.getCash()).setKaspiChecked(true).setGoodsChecked(true)
                        .setClosedAt(at.plusMinutes(50)).setAcceptedBy(staff(c.getId(), Role.OPERATOR).get(0).getName());
            }
        }
    }

    private void deliver(Trip t, Order o, LocalDateTime at) {
        String who = t.getExpeditor().getName();
        int roll = rnd.nextInt(12);
        if (roll == 0) {
            o.setStatus(OrderStatus.REFUSED).setRefuseReason("Магазин закрыт");
            o.event(at, who, "Отказ магазина: магазин закрыт");
            return;
        }
        for (OrderLine l : o.getLines()) l.setDelivered(l.getQty());
        if (roll <= 2 && !o.getLines().isEmpty()) {
            OrderLine l = o.getLines().get(0);
            l.setDelivered(Math.max(0, l.getQty() - 1 - rnd.nextInt(Math.max(1, l.getQty() / 3))));
            o.setStatus(OrderStatus.PARTIAL);
            o.event(at, who, "Выдано частично: магазин взял меньше");
        } else {
            o.setStatus(OrderStatus.DELIVERED);
            o.event(at, who, "Выдано полностью");
        }
        long returnSum = 0;
        if (rnd.nextInt(3) == 0) {
            ProductReturn r = new ProductReturn().setId(seq++).setCompany(o.getCompany()).setOutlet(o.getOutlet())
                    .setTrip(t).setDate(today).setByName(who);
            List<Product> cat = products(o.getCompany().getId());
            ReturnReason[] reasons = ReturnReason.values();
            int n = 1 + rnd.nextInt(2);
            for (int i = 0; i < n; i++) {
                Product p = cat.get(rnd.nextInt(cat.size()));
                r.getLines().add(new ReturnLine().setProduct(p).setQty(1 + rnd.nextInt(3))
                        .setPrice(p.price(o.getOutlet().getPriceType())).setReason(reasons[rnd.nextInt(reasons.length)]));
            }
            returns.add(r);
            t.getReturns().add(r);
            returnSum = r.getTotal();
            int[] s = stock.computeIfAbsent(r.getLines().get(0).getProduct(), k -> new int[2]);
            s[1] += r.getQty();
            o.event(at.plusMinutes(2), who, "Принят возврат негодного: " + money(returnSum));
        }
        long due = Math.max(0, o.getDeliveredTotal() - returnSum);
        if (o.getPayment() != PaymentMethod.CREDIT && due > 0) {
            Payment p = new Payment().setId(seq++).setCompany(o.getCompany()).setOutlet(o.getOutlet()).setOrder(o)
                    .setTrip(t).setMethod(o.getPayment()).setAmount(due).setAt(at.plusMinutes(3)).setByName(who);
            payments.add(p);
            t.getPayments().add(p);
            o.event(at.plusMinutes(3), who, "Оплата: " + o.getPayment().getLabel().toLowerCase() + ", " + money(due));
        }
        if (o.getOutlet().getDebt() > 0 && rnd.nextInt(4) == 0) {
            long part = Math.min(o.getOutlet().getDebt(), (10 + rnd.nextInt(20)) * 1000L);
            Payment p = new Payment().setId(seq++).setCompany(o.getCompany()).setOutlet(o.getOutlet()).setTrip(t)
                    .setMethod(PaymentMethod.CASH).setAmount(part).setAt(at.plusMinutes(4)).setByName(who);
            payments.add(p);
            t.getPayments().add(p);
            o.getOutlet().setDebt(o.getOutlet().getDebt() - part).setLastPaymentDate(today).setLastPaymentSum(part);
        }
    }

    private void receiptsFor(Company c) {
        List<Product> cat = products(c.getId());
        String from = c.isOwn() ? "Производство «Юг Сладости»" : "Производство «Юг Сладости» → " + c.getCrmClient();
        Receipt draft = new Receipt().setId(seq++).setNumber("П-" + seq).setCompany(c).setSource(ReceiptSource.CRM)
                .setStatus(ReceiptStatus.DRAFT).setDate(today).setSupplier(from)
                .setBasis("Отгрузка CRM, заказ №" + (2400 + c.getId()) + " от " + today.minusDays(1));
        Receipt done = new Receipt().setId(seq++).setNumber("П-" + seq).setCompany(c).setSource(ReceiptSource.CRM)
                .setStatus(ReceiptStatus.CONFIRMED).setDate(today.minusDays(3)).setSupplier(from)
                .setBasis("Отгрузка CRM, заказ №" + (2300 + c.getId())).setConfirmedBy(staff(c.getId(), Role.STOREKEEPER).get(0).getName());
        Receipt other = new Receipt().setId(seq++).setNumber("П-" + seq).setCompany(c).setSource(ReceiptSource.SUPPLIER)
                .setStatus(ReceiptStatus.CONFIRMED).setDate(today.minusDays(5)).setSupplier("[Поставщик вафель и зефира]")
                .setBasis("Накладная поставщика").setConfirmedBy(staff(c.getId(), Role.STOREKEEPER).get(0).getName());
        for (Product p : cat) {
            if (p.getCrmCode() == null) {
                other.getLines().add(new ReceiptLine().setProduct(p).setExpected(p.getPerBox() * 10).setActual(p.getPerBox() * 10));
            } else if (rnd.nextBoolean()) {
                draft.getLines().add(new ReceiptLine().setProduct(p).setExpected(p.getPerBox() * (4 + rnd.nextInt(10))));
            } else {
                int q = p.getPerBox() * (5 + rnd.nextInt(12));
                done.getLines().add(new ReceiptLine().setProduct(p).setExpected(q).setActual(q));
            }
        }
        if (draft.getLines().isEmpty()) {
            Product p = cat.get(0);
            draft.getLines().add(new ReceiptLine().setProduct(p).setExpected(p.getPerBox() * 6));
        }
        receipts.addAll(List.of(draft, done, other));
    }

    // ------------------------------------------------------------------ служебное

    private static <T> List<T> scope(List<T> list, Long cid, Function<T, Company> company) {
        if (cid == null) return list;
        return list.stream().filter(x -> company.apply(x) != null && cid.equals(company.apply(x).getId()))
                .collect(Collectors.toList());
    }

    private static <T> T find(List<T> list, Long id, Function<T, Long> idOf) {
        if (id == null) return null;
        return list.stream().filter(x -> id.equals(idOf.apply(x))).findFirst().orElse(null);
    }

    private static String money(long v) {
        return String.format(Locale.ROOT, "%,d", v).replace(',', ' ') + " ₸";
    }
}
