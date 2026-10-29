package com.confectionery.distribution.demo;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import com.confectionery.distribution.service.Actor;
import com.confectionery.distribution.service.CashService;
import com.confectionery.distribution.service.StockService;
import com.confectionery.distribution.tenant.TenantContext;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

/**
 * Профиль demo: три компании с командами, магазинами, заказами, рейсами и кассой — как были заглушки
 * админки, но в базе и с настоящими движениями товара и денег. Только при пустой базе.
 *
 * <p>Пароль всех демо-сотрудников — из переменной DEMO_PASSWORD (в репозитории паролей нет).
 * Телефоны для входа: +7 701 000 КК СС, где КК — id компании, СС — номер сотрудника в ней.
 */
@Slf4j
@Component
@Profile("demo")
@RequiredArgsConstructor
public class DemoSeeder implements ApplicationRunner {

    private final CompanyRepository companies;
    private final CompanySettingsRepository settings;
    private final EmployeeRepository employees;
    private final RegionRepository regions;
    private final PriceTypeRepository priceTypes;
    private final OutletRepository outlets;
    private final OutletOpeningDebtRepository openingDebts;
    private final ProductRepository products;
    private final PriceRepository prices;
    private final VehicleRepository vehicles;
    private final WarehouseRepository warehouses;
    private final ReceiptRepository receipts;
    private final VisitRepository visits;
    private final OrderRepository orders;
    private final TripRepository trips;
    private final TripOrderRepository tripOrders;
    private final DeliveryRepository deliveries;
    private final PaymentRepository payments;
    private final ProductReturnRepository returns;
    private final StockService stock;
    private final CashService cash;
    private final DemoTracks tracks;
    private final PasswordEncoder encoder;
    private final TransactionTemplate tx;
    private final Clock clock;

    @Value("${DEMO_PASSWORD:}")
    private String demoPassword;

    private final Random rnd = new Random(42);
    private LocalDate today;
    private LocalDateTime now;
    private String hash;
    private int orderNo = 1000;

    /** Всё о компании, что нужно при заполнении. */
    private static class Co {
        Company c;
        PriceType wholesale, retail;
        Warehouse main, defect;
        String prefix;
        int staffNo;
        Employee director, operator, storekeeper;
        final List<Product> products = new ArrayList<>();
        final List<Employee> agents = new ArrayList<>();
        final List<Employee> expeditors = new ArrayList<>();
        final Map<Employee, List<Group>> groupsOf = new LinkedHashMap<>();
        final Map<Outlet, Long> opening = new HashMap<>();
    }

    @Override
    public void run(ApplicationArguments args) {
        TenantContext.run(TenantContext.ROOT, () -> {
            if (companies.count() > 0) {
                Integer filled = tx.execute(s -> fillCoordinates());
                Integer days = tx.execute(s -> tracks.fill());
                log.info("Демо-данные не нужны: в базе уже есть компании" + (filled > 0 ? "; координаты для карты добавлены: " + filled : "")
                        + (days > 0 ? "; треки GPS и журнал приложения добавлены, дней: " + days : ""));
                return;
            }
            if (demoPassword == null || demoPassword.isBlank())
                throw new IllegalStateException("Профиль demo: задайте DEMO_PASSWORD (пароль демо-сотрудников) в .env или окружении");
            tx.executeWithoutResult(s -> build());
            log.info("Демо-данные созданы: 3 компании, вход по телефонам +7 701 000 КК СС с паролем из DEMO_PASSWORD");
        });
    }

    // ------------------------------------------------------------------ данные

    private static final String[] SHOPS = {"Асель", "Береке", "Дос-Маркет", "Нур", "Жулдыз", "Самал", "Айгуль",
            "Мерей", "Алтын", "Шанырак", "Ак Жол", "Улан", "Достык", "Арман", "Сая", "Камила", "Мирас", "Тумар",
            "Аружан", "Нурлы", "Сункар", "Асем", "Баян", "Сапа", "Ырыс", "Кайнар", "Ажар", "Орда", "Дана", "Томирис",
            "Бахыт", "Алма", "Жанар", "Ару", "Мадина", "Сымбат", "Ерке", "Гульдер", "Айдана", "Карлыгаш", "Ботагоз",
            "Даулет", "Нурай", "Акбота", "Жаркын", "Самгау", "Кулагер", "Байтерек", "Мейрам", "Береке-2"};
    private static final String[] STREETS = {"ул. Абая", "ул. Толе би", "ул. Байтурсынова", "ул. Жибек жолы",
            "пр. Республики", "ул. Момышулы", "ул. Казыбек би", "ул. Сейфуллина", "мкр. Нурсат", "мкр. Самал",
            "ул. Кунаева", "ул. Аль-Фараби", "ул. Туркестанская", "ул. Желтоксан"};
    private static final String[] OWNERS = {"Нурлан А.", "Гульмира С.", "Ерлан Б.", "Айжан К.", "Бакыт Т.",
            "Сауле М.", "Арман Ж.", "Динара Е.", "Кайрат О.", "Жанна Н.", "Марат С.", "Алия Р."};
    private static final String[] NO_ORDER = {"Товар ещё есть", "Нет денег", "Хозяина нет на месте"};

    private void build() {
        today = LocalDate.now(clock);
        now = LocalDateTime.now(clock);
        hash = encoder.encode(demoPassword);

        Co c1 = company("Своя доставка", "Даурен Абдиев", null, true, "С");
        Co c2 = company("Склад-дилер А", "Серик Жумабаев", "ТОО «Дилер А»", false, "А");
        Co c3 = company("Склад-дилер Б", "Гульнара Ахметова", "ИП «Дилер Б»", false, "Б");

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

        for (Co co : List.of(c1, c2, c3)) {
            initialStock(co);
            receiptsFor(co);
            ordersAndTrips(co);
        }
        // один агент давно не выходил на связь, у другого на телефоне ждут сети — для «Требует внимания»
        for (Co co : List.of(c1, c2, c3)) {
            for (Employee a : co.agents) {
                if ("Бауыржан С.".equals(a.getName())) a.setLastSync(now.minusHours(26)).setUnsent(0);
                if ("Ержан Т.".equals(a.getName())) a.setUnsent(3);
            }
        }
        tracks.fill();
    }

    private Co company(String name, String director, String crmClient, boolean own, String prefix) {
        Co co = new Co();
        co.prefix = prefix;
        co.c = companies.save(new Company().setName(name).setDirector(director).setCrmClient(crmClient).setOwn(own)
                .setPhone("+7 700 000 0" + (companies.count() + 1) + " 00").setCreatedAt(now.minusMonths(3)));
        CompanySettings st = new CompanySettings();
        st.setCompany(co.c);
        settings.save(st);
        co.wholesale = priceType(co.c, PriceKind.WHOLESALE);
        co.retail = priceType(co.c, PriceKind.RETAIL);
        co.main = warehouse(co.c, WarehouseType.MAIN, "Основной склад", null);
        co.defect = warehouse(co.c, WarehouseType.DEFECT, "Негодный товар", null);
        return co;
    }

    private PriceType priceType(Company c, PriceKind kind) {
        PriceType t = new PriceType().setCode(kind).setName(kind.getLabel());
        t.setCompany(c);
        return priceTypes.save(t);
    }

    private Warehouse warehouse(Company c, WarehouseType type, String name, Vehicle v) {
        Warehouse w = new Warehouse().setType(type).setName(name).setVehicle(v);
        w.setCompany(c);
        return warehouses.save(w);
    }

    private Employee person(Co co, String name, Role role) {
        String phone = "+7701000" + String.format("%02d%02d", co.c.getId(), ++co.staffNo);
        Employee e = new Employee().setName(name).setRole(role).setPhone(phone).setPasswordHash(hash)
                .setMustChangePassword(false).setCreatedAt(now.minusMonths(2));
        e.setCompany(co.c);
        return employees.save(e);
    }

    private void staff(Co co, String director, String operator, String storekeeper) {
        co.director = person(co, director, Role.DIRECTOR);
        co.operator = person(co, operator, Role.OPERATOR);
        co.storekeeper = person(co, storekeeper, Role.STOREKEEPER);
    }

    private void catalog(Co co, int pricePercent) {
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
            Product p = new Product().setName((String) it[0]).setCategory((String) it[1]).setPerBox((int) it[2])
                    .setCrmCode((String) it[5]).setBarcode("487000" + String.format("%07d", 1000 + n++));
            p.setCompany(co.c);
            products.save(p);
            p.setWholesale(round10((int) it[3] * pricePercent / 100)).setRetail(round10((int) it[4] * pricePercent / 100));
            price(co, p, co.wholesale, p.getWholesale());
            price(co, p, co.retail, p.getRetail());
            co.products.add(p);
        }
    }

    private void price(Co co, Product p, PriceType t, long value) {
        Price pr = new Price().setProduct(p).setPriceType(t).setValidFrom(today.minusDays(60)).setPrice(value);
        pr.setCompany(co.c);
        prices.save(pr);
    }

    private static long round10(long v) {
        return Math.round(v / 10.0) * 10;
    }

    /** Пачка магазинов торгового в районе — для раскладки точек на карте и демо-заказов. */
    private record Group(Region region, String name, Employee agent, List<Outlet> outlets) {
    }

    /** Районы, агенты, по две пачки магазинов на агента: первую обходят сегодня, вторую обходили вчера. */
    private int network(Co co, String[] regionNames, String[] agentNames, int shop) {
        List<Region> rs = new ArrayList<>();
        for (String rn : regionNames) {
            Region r = new Region().setName(rn);
            r.setCompany(co.c);
            rs.add(regions.save(r));
        }
        int[] groupNo = new int[rs.size()];
        for (int i = 0; i < agentNames.length; i++) {
            Employee a = person(co, agentNames[i], Role.AGENT);
            a.setLastSync(now.minusMinutes(5 + rnd.nextInt(80)));
            co.agents.add(a);
            Region r = rs.get(i % rs.size());
            List<Group> mine = new ArrayList<>();
            for (int k = 0; k < 2; k++) {
                Group g = new Group(r, r.getName() + "-" + (++groupNo[i % rs.size()]), a, new ArrayList<>());
                int count = 5 + rnd.nextInt(3);
                for (int j = 0; j < count; j++) g.outlets().add(outlet(co, g, shop++));
                mine.add(g);
            }
            co.groupsOf.put(a, mine);
        }
        return shop;
    }

    private Outlet outlet(Co co, Group group, int n) {
        String name = n < SHOPS.length ? "Магазин «" + SHOPS[n] + "»" : "Магазин №" + (n + 1);
        boolean retail = rnd.nextInt(5) == 0;
        long limit = retail ? 50_000 : (rnd.nextBoolean() ? 100_000 : 150_000);
        long debt = rnd.nextInt(10) < 4 ? 0 : (5_000 + rnd.nextInt(130) * 1_000L);
        boolean overdue = debt > 20_000 && rnd.nextInt(6) == 0;
        Outlet o = new Outlet().setName(name)
                .setLegal((rnd.nextInt(4) == 0 ? "ТОО «" : "ИП «") + (n < SHOPS.length ? SHOPS[n] : "№" + (n + 1)) + "»")
                .setOwner(OWNERS[n % OWNERS.length])
                .setPhone("+7 7" + (n % 3 == 0 ? "01" : n % 3 == 1 ? "05" : "47") + " 000 " + String.format("%02d %02d", n / 100, n % 100))
                .setAddress(STREETS[n % STREETS.length] + ", " + (3 + rnd.nextInt(140)))
                .setPriceType(retail ? co.retail : co.wholesale).setCreditLimit(limit)
                .setPaymentDays(retail ? 3 : 7).setCreatedAt(today.minusDays(30 + rnd.nextInt(400))).setCreatedBy("импорт Doctor Sales");
        if (n % 23 == 7) {
            o.setStatus(OutletStatus.PENDING).setCreatedAt(today).setCreatedBy(group.agent().getName());
            debt = 0;
        } else if (n % 37 == 11) {
            o.setStatus(OutletStatus.CLOSED);
            debt = 0;
        }
        double[] g = DemoGeo.outlet(group.region().getName(), group.name(), group.outlets().size(), n);
        o.setLat(g[0]).setLng(g[1]).setAgent(group.agent()).setRegion(group.region());
        o.setCompany(co.c);
        outlets.save(o);
        if (debt > 0) {
            // просроченный долг — старше отсрочки, остальные ещё в сроке
            LocalDate asOf = overdue ? today.minusDays(o.getPaymentDays() + 5 + rnd.nextInt(20)) : today.minusDays(rnd.nextInt(o.getPaymentDays()));
            openingDebt(co, o, debt, asOf);
        }
        return o;
    }

    private void openingDebt(Co co, Outlet o, long amount, LocalDate asOf) {
        OutletOpeningDebt d = new OutletOpeningDebt().setOutlet(o).setAmount(amount).setAsOf(asOf).setNote("импорт Doctor Sales");
        d.setCompany(co.c);
        openingDebts.save(d);
        co.opening.merge(o, amount, Long::sum);
    }

    private void expeditors(Co co, String[] names, String[] plates, String model) {
        for (int i = 0; i < names.length; i++) {
            Employee e = person(co, names[i], Role.EXPEDITOR);
            e.setLastSync(now.minusMinutes(3 + rnd.nextInt(40)));
            Vehicle v = new Vehicle().setPlate(plates[i]).setModel(model).setExpeditor(e);
            v.setCompany(co.c);
            vehicles.save(v);
            warehouse(co.c, WarehouseType.VEHICLE, "Машина " + plates[i], v);
            co.expeditors.add(e);
        }
    }

    private void initialStock(Co co) {
        Actor who = new Actor(co.storekeeper, co.storekeeper.getName());
        for (Product p : co.products) {
            stock.move(p, p.getPerBox() * (40 + rnd.nextInt(40)), null, co.main, MovementReason.ADJUST, who,
                    today.minusDays(10).atTime(9, 0), m -> m.setNote("Остатки на начало"));
        }
    }

    private void receiptsFor(Co co) {
        String from = co.c.isOwn() ? "Производство «Юг Сладости»" : "Производство «Юг Сладости» → " + co.c.getCrmClient();
        Receipt draft = receipt(co, ReceiptSource.CRM, today, from, "Отгрузка CRM, заказ №" + (2400 + co.c.getId()) + " от " + today.minusDays(1));
        Receipt done = receipt(co, ReceiptSource.CRM, today.minusDays(3), from, "Отгрузка CRM, заказ №" + (2300 + co.c.getId()));
        Receipt other = receipt(co, ReceiptSource.SUPPLIER, today.minusDays(5), "[Поставщик вафель и зефира]", "Накладная поставщика");
        for (Product p : co.products) {
            if (p.getCrmCode() == null) other.addLine(new ReceiptLine().setProduct(p).setExpected(p.getPerBox() * 10));
            else if (rnd.nextBoolean()) draft.addLine(new ReceiptLine().setProduct(p).setExpected(p.getPerBox() * (4 + rnd.nextInt(10))));
            else done.addLine(new ReceiptLine().setProduct(p).setExpected(p.getPerBox() * (5 + rnd.nextInt(12))));
        }
        if (draft.getLines().isEmpty()) draft.addLine(new ReceiptLine().setProduct(co.products.get(0)).setExpected(co.products.get(0).getPerBox() * 6));
        for (Receipt r : List.of(draft, done, other)) receipts.save(r);
        Actor who = new Actor(co.storekeeper, co.storekeeper.getName());
        for (Receipt r : List.of(done, other)) {
            stock.confirmReceipt(r.getId(), Map.of(), who);
            r.setConfirmedAt(r.getDate().atTime(10, 30));
        }
    }

    private Receipt receipt(Co co, ReceiptSource source, LocalDate date, String supplier, String basis) {
        Receipt r = new Receipt().setNumber("П-" + co.prefix + "-" + (receipts.count() + 101)).setSource(source)
                .setStatus(ReceiptStatus.DRAFT).setDate(date).setSupplier(supplier).setBasis(basis).setWarehouse(co.main)
                .setCreatedAt(date.atTime(9, 0));
        r.setCompany(co.c);
        return receipts.save(r);
    }

    // ------------------------------------------------------------------ заказы, рейсы, касса

    private Order newOrder(Co co, Outlet o, Employee agent, Visit visit, LocalDateTime created, LocalDate delivery) {
        Order order = new Order().setNumber(co.prefix + "-" + (++orderNo)).setOutlet(o).setAgent(agent).setVisit(visit)
                .setCreatedAt(created).setDeliveryDate(delivery).setStatus(OrderStatus.ACCEPTED);
        order.setCompany(co.c);
        int lines = 2 + rnd.nextInt(4);
        Set<Product> used = new HashSet<>();
        for (int i = 0; i < lines; i++) {
            Product p = co.products.get(rnd.nextInt(co.products.size()));
            if (!used.add(p)) continue;
            int qty = p.getPerBox() <= 4 ? 1 + rnd.nextInt(4) : p.getPerBox() * (1 + rnd.nextInt(2)) / (rnd.nextBoolean() ? 1 : 2);
            order.addLine(new OrderLine().setProduct(p).setQty(qty).setPrice(p.price(o.getPriceType().getCode())));
        }
        int pm = rnd.nextInt(10);
        order.setPayment(pm < 6 ? PaymentMethod.CASH : pm < 8 ? PaymentMethod.KASPI : PaymentMethod.CREDIT);
        order.event(created, agent, agent.getName(), "Оформил заказ в магазине (с телефона)");
        return orders.save(order);
    }

    private Visit visit(Co co, Employee agent, Outlet o, LocalDateTime at, VisitResult result) {
        Visit v = new Visit().setAgent(agent).setOutlet(o).setStartedAt(at).setFinishedAt(at.plusMinutes(6 + rnd.nextInt(10)))
                .setDistance(rnd.nextInt(120)).setResult(result)
                .setRefuseReason(result == VisitResult.NO_ORDER ? NO_ORDER[rnd.nextInt(NO_ORDER.length)] : null);
        visitPlace(v);
        v.setCompany(co.c);
        return visits.save(v);
    }

    /** Где был телефон агента при визите: в distance метрах от магазина. */
    private static void visitPlace(Visit v) {
        Outlet o = v.getOutlet();
        if (o.getLat() == null || o.getLng() == null) return;
        double[] g = DemoGeo.near(o.getLat(), o.getLng(), v.getDistance() == null ? 0 : v.getDistance(), v.getStartedAt().hashCode() + o.getName().hashCode());
        v.setLat(g[0]).setLng(g[1]);
    }

    /** Где был телефон экспедитора при выдаче: у магазина. */
    private static void deliveryPlace(Delivery d) {
        Outlet o = d.getOrder().getOutlet();
        if (o.getLat() == null || o.getLng() == null) return;
        double[] g = DemoGeo.near(o.getLat(), o.getLng(), 25, d.getDeliveredAt().hashCode() + o.getName().hashCode());
        d.setLat(g[0]).setLng(g[1]);
    }

    /**
     * Демо-база, созданная до карты: магазинам без координат — точки по их районам, визитам и выдачам
     * без отметки места — рядом с магазином. Возвращает, сколько магазинов получили координаты.
     */
    private int fillCoordinates() {
        int n = 0;
        for (Outlet o : outlets.findAll()) {
            if (o.getLat() != null && o.getLng() != null) continue;
            String region = o.getRegion() == null ? null : o.getRegion().getName();
            double[] g = DemoGeo.outlet(region, region == null ? null : region + "-1", (int) (o.getId() % 7), o.getId());
            o.setLat(g[0]).setLng(g[1]);
            n++;
        }
        for (Visit v : visits.findAll()) if (v.getLat() == null) visitPlace(v);
        for (Delivery d : deliveries.findAll()) if (d.getLat() == null) deliveryPlace(d);
        return n;
    }

    private void ordersAndTrips(Co co) {
        List<Order> forToday = new ArrayList<>();
        for (Employee a : co.agents) {
            List<Group> rs = co.groupsOf.get(a);
            // вчерашние заказы (второй маршрут агента) — сегодня их развозят экспедиторы
            for (Outlet o : rs.get(1).outlets()) {
                if (o.getStatus() != OutletStatus.ACTIVE) continue;
                LocalDateTime at = today.minusDays(1).atTime(9 + rnd.nextInt(8), rnd.nextInt(60));
                if (rnd.nextInt(10) < 3) {
                    visit(co, a, o, at, VisitResult.NO_ORDER);
                    continue;
                }
                Order ord = newOrder(co, o, a, visit(co, a, o, at, VisitResult.ORDER), at.plusMinutes(4), today);
                ord.setStatus(OrderStatus.IN_TRIP);
                ord.event(today.atTime(7, 40), null, "Склад", "Собран и загружен в машину");
                forToday.add(ord);
            }
            // сегодняшние заказы (первый маршрут) — доставка завтра
            int taken = 0;
            for (Outlet o : rs.get(0).outlets()) {
                if (o.getStatus() == OutletStatus.CLOSED) continue;
                LocalDateTime at = today.atTime(9, 0).plusMinutes(25L * taken + rnd.nextInt(20));
                if (at.isAfter(now)) {
                    if (taken > 0) continue; // агент ещё не дошёл
                    at = now.minusMinutes(5);
                }
                if (rnd.nextInt(10) < 3) {
                    visit(co, a, o, at, VisitResult.NO_ORDER);
                    continue;
                }
                Order ord = newOrder(co, o, a, visit(co, a, o, at, VisitResult.ORDER), at.plusMinutes(4), today.plusDays(1));
                taken++;
                long debt = co.opening.getOrDefault(o, 0L);
                if (ord.getPayment() == PaymentMethod.CREDIT && debt + ord.getTotal() > o.getCreditLimit()) {
                    needsApproval(ord, debt);
                } else if (rnd.nextInt(5) == 0) {
                    ord.setStatus(OrderStatus.ASSEMBLED);
                    ord.event(now.minusMinutes(20), co.storekeeper, "Склад", "Собран");
                }
            }
        }
        List<Order> all = orders.findAll().stream().filter(o -> co.c.getId().equals(o.getCompanyId())).toList();
        // хотя бы один заказ сверх лимита долга в каждой компании — чтобы было что разрешать
        if (all.stream().noneMatch(o -> o.getStatus() == OrderStatus.NEEDS_APPROVAL)) {
            all.stream().filter(o -> o.getStatus() == OrderStatus.ACCEPTED && o.getOutlet().getCreditLimit() > o.getTotal())
                    .findFirst().ifPresent(o -> {
                        long debt = o.getOutlet().getCreditLimit() - o.getTotal() / 2 - co.opening.getOrDefault(o.getOutlet(), 0L);
                        if (debt > 0) openingDebt(co, o.getOutlet(), debt, today.minusDays(2));
                        o.setPayment(PaymentMethod.CREDIT);
                        needsApproval(o, co.opening.getOrDefault(o.getOutlet(), 0L));
                    });
        }
        // одна отмена — для вида
        all.stream().filter(o -> o.getStatus() == OrderStatus.ACCEPTED).findFirst().ifPresent(o -> {
            o.setStatus(OrderStatus.CANCELLED);
            o.event(now.minusMinutes(30), co.operator, co.operator.getName() + " (оператор)", "Отменил: магазин попросил перенести");
        });
        trips(co, forToday);
    }

    private void needsApproval(Order o, long debt) {
        o.setStatus(OrderStatus.NEEDS_APPROVAL);
        o.event(o.getCreatedAt().plusMinutes(1), null, "Система", "Долг станет " + money(debt + o.getTotal())
                + " при лимите " + money(o.getOutlet().getCreditLimit()) + " — нужно разрешение");
    }

    private void trips(Co co, List<Order> forToday) {
        List<Employee> exps = co.expeditors;
        TripStatus[] plan = co.c.isOwn() ? new TripStatus[]{TripStatus.ON_ROAD, TripStatus.RETURNED}
                : exps.size() > 1 ? new TripStatus[]{TripStatus.ON_ROAD, TripStatus.CLOSED} : new TripStatus[]{TripStatus.ON_ROAD};
        List<Vehicle> cars = vehicles.findAll().stream().filter(v -> co.c.getId().equals(v.getCompanyId())).toList();
        for (int i = 0; i < exps.size(); i++) {
            Employee e = exps.get(i);
            Vehicle car = cars.stream().filter(v -> e.equals(v.getExpeditor())).findFirst().orElseThrow();
            Warehouse carStock = stock.warehouse(car);
            Trip t = new Trip().setNumber("Р-" + co.prefix + "-" + today.getDayOfMonth() + String.format("%02d", i + 1))
                    .setDate(today).setExpeditor(e).setVehicle(car).setStatus(TripStatus.ON_ROAD)
                    .setStartedAt(today.atTime(8, 10 + 10 * i));
            t.setCompany(co.c);
            trips.save(t);
            int pos = 0;
            for (int k = i; k < forToday.size(); k += exps.size()) {
                Order o = forToday.get(k);
                TripOrder to = new TripOrder().setTrip(t).setOrder(o).setPosition(pos++);
                to.setCompany(co.c);
                t.getTripOrders().add(tripOrders.save(to));
                for (OrderLine l : o.getLines()) {
                    stock.move(l.getProduct(), l.getQty(), co.main, carStock, MovementReason.LOAD, new Actor(co.storekeeper, "Склад"),
                            today.atTime(7, 40), m -> m.setTrip(t).setOrder(o));
                }
            }
            int done = plan[i] == TripStatus.ON_ROAD ? t.getStops() * 2 / 5 + 1 : t.getStops();
            LocalDateTime at = today.atTime(9, 0);
            List<Order> stops = t.getOrders();
            for (int k = 0; k < Math.min(done, stops.size()); k++) {
                at = at.plusMinutes(18 + rnd.nextInt(15));
                if (at.isAfter(now)) at = now.minusMinutes(stops.size() - k);
                deliver(co, t, carStock, stops.get(k), at);
            }
            if (plan[i] != TripStatus.ON_ROAD) t.setStatus(TripStatus.RETURNED).setReturnedAt(at.plusMinutes(30));
            if (plan[i] == TripStatus.CLOSED) {
                cash.accept(t.getId(), t.getCash(), true, true, new Actor(co.operator, co.operator.getName() + " (оператор)"));
                t.setClosedAt(at.plusMinutes(50));
                t.getHandover().setAcceptedAt(at.plusMinutes(50));
            }
        }
    }

    private void deliver(Co co, Trip t, Warehouse carStock, Order o, LocalDateTime at) {
        Employee exp = t.getExpeditor();
        String who = exp.getName();
        Actor actor = new Actor(exp, who);
        Delivery d = new Delivery().setOrder(o).setTrip(t).setDeliveredAt(at).setExpeditor(exp);
        deliveryPlace(d);
        d.setCompany(co.c);
        int roll = rnd.nextInt(12);
        if (roll == 0) {
            d.setStatus(DeliveryStatus.REFUSED).setRefuseReason("Магазин закрыт");
            o.getDeliveries().add(deliveries.save(d));
            o.setStatus(OrderStatus.REFUSED).setRefuseReason("Магазин закрыт");
            o.event(at, exp, who, "Отказ магазина: магазин закрыт");
            return;
        }
        boolean partial = roll <= 2;
        for (int i = 0; i < o.getLines().size(); i++) {
            OrderLine l = o.getLines().get(i);
            int q = partial && i == 0 ? Math.max(0, l.getQty() - 1 - rnd.nextInt(Math.max(1, l.getQty() / 3))) : l.getQty();
            d.addItem(new DeliveryItem().setProduct(l.getProduct()).setQty(q).setPrice(l.getNetPrice()));
            if (q > 0) stock.move(l.getProduct(), q, carStock, null, MovementReason.DELIVERY, actor, at, m -> m.setTrip(t).setOrder(o));
        }
        d.setStatus(partial ? DeliveryStatus.PARTIAL : DeliveryStatus.DELIVERED);
        o.getDeliveries().add(deliveries.save(d));
        o.setStatus(partial ? OrderStatus.PARTIAL : OrderStatus.DELIVERED);
        o.event(at, exp, who, partial ? "Выдано частично: магазин взял меньше" : "Выдано полностью");

        long returnSum = 0;
        if (rnd.nextInt(3) == 0) {
            ProductReturn r = new ProductReturn().setOutlet(o.getOutlet()).setTrip(t).setOrder(o).setDate(today)
                    .setCreatedAt(at.plusMinutes(2)).setReceivedBy(exp);
            r.setCompany(co.c);
            int n = 1 + rnd.nextInt(2);
            for (int i = 0; i < n; i++) {
                Product p = co.products.get(rnd.nextInt(co.products.size()));
                r.addLine(new ReturnLine().setProduct(p).setQty(1 + rnd.nextInt(3))
                        .setPrice(p.price(o.getOutlet().getPriceType().getCode())).setReason(ReturnReason.values()[rnd.nextInt(ReturnReason.values().length)]));
            }
            returns.save(r);
            t.getReturns().add(r);
            for (ReturnLine l : r.getLines())
                stock.move(l.getProduct(), l.getQty(), null, carStock, MovementReason.RETURN, actor, at.plusMinutes(2), m -> m.setTrip(t).setProductReturn(r));
            returnSum = r.getTotal();
            o.event(at.plusMinutes(2), exp, who, "Принят возврат негодного: " + money(returnSum));
        }
        long due = Math.max(0, o.getDeliveredTotal() - returnSum);
        if (o.getPayment() != PaymentMethod.CREDIT && due > 0) {
            pay(co, t, o.getOutlet(), o, o.getPayment(), due, at.plusMinutes(3), exp);
            o.event(at.plusMinutes(3), exp, who, "Оплата: " + o.getPayment().getLabel().toLowerCase() + ", " + money(due));
        }
        long old = co.opening.getOrDefault(o.getOutlet(), 0L);
        if (old > 0 && rnd.nextInt(4) == 0) {
            long part = Math.min(old, (10 + rnd.nextInt(20)) * 1000L);
            pay(co, t, o.getOutlet(), null, PaymentMethod.CASH, part, at.plusMinutes(4), exp);
            co.opening.put(o.getOutlet(), old - part);
        }
    }

    private void pay(Co co, Trip t, Outlet outlet, Order order, PaymentMethod method, long amount, LocalDateTime at, Employee by) {
        Payment p = new Payment().setOutlet(outlet).setOrder(order).setTrip(t).setMethod(method).setAmount(amount).setAt(at).setReceivedBy(by);
        p.setCompany(co.c);
        t.getPayments().add(payments.save(p));
    }

    private static String money(long v) {
        return String.format(Locale.ROOT, "%,d", v).replace(',', ' ') + " ₸";
    }
}
