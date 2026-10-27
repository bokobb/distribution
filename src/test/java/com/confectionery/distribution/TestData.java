package com.confectionery.distribution;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import com.confectionery.distribution.service.Actor;
import com.confectionery.distribution.service.StockService;
import com.confectionery.distribution.tenant.TenantContext;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.test.context.TestComponent;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Supplier;

/**
 * Данные для тестов: каждая компания — новая, поэтому тесты не мешают друг другу в общей базе.
 * Пишет без фильтра компании (как служебная задача), каждый вызов — своя транзакция.
 */
@TestComponent
@RequiredArgsConstructor
public class TestData {

    private static final AtomicLong SEQ = new AtomicLong(1);

    private final CompanyRepository companies;
    private final EmployeeRepository employees;
    private final RegionRepository regions;
    private final RouteRepository routes;
    private final RouteOutletRepository routeOutlets;
    private final PriceTypeRepository priceTypes;
    private final OutletRepository outlets;
    private final OutletOpeningDebtRepository openingDebts;
    private final ProductRepository products;
    private final VehicleRepository vehicles;
    private final WarehouseRepository warehouses;
    private final OrderRepository orders;
    private final TripRepository trips;
    private final TripOrderRepository tripOrders;
    private final DeliveryRepository deliveries;
    private final PaymentRepository payments;
    private final ProductReturnRepository returns;
    private final StockService stock;
    private final TransactionTemplate tx;
    private final Clock clock;
    private final PasswordEncoder encoder;
    private final JdbcTemplate jdbc;

    /** Компания с одним магазином, товаром, агентом, экспедитором с машиной и оператором. */
    public record World(Company company, Employee operator, Employee agent, Employee expeditor, Route route,
                        PriceType wholesale, Product product, Outlet outlet, Vehicle vehicle,
                        Warehouse main, Warehouse defect, Warehouse car) {
        public Long id() {
            return company.getId();
        }
    }

    private <T> T root(Supplier<T> action) {
        return TenantContext.asRoot(() -> tx.execute(s -> action.get()));
    }

    public LocalDate today() {
        return LocalDate.now(clock);
    }

    public World world(String name) {
        return root(() -> {
            long n = SEQ.getAndIncrement();
            Company c = companies.save(new Company().setName(name + " " + n).setCreatedAt(LocalDateTime.now(clock)));
            PriceType wholesale = save(priceTypes, new PriceType().setCode(PriceKind.WHOLESALE).setName("Опт"), c);
            save(priceTypes, new PriceType().setCode(PriceKind.RETAIL).setName("Розница"), c);
            Warehouse main = save(warehouses, new Warehouse().setType(WarehouseType.MAIN).setName("Основной"), c);
            Warehouse defect = save(warehouses, new Warehouse().setType(WarehouseType.DEFECT).setName("Негодный"), c);
            Employee operator = person(c, "Оператор " + n, Role.OPERATOR);
            Employee agent = person(c, "Агент " + n, Role.AGENT);
            Employee expeditor = person(c, "Экспедитор " + n, Role.EXPEDITOR);
            Vehicle v = save(vehicles, new Vehicle().setPlate("T " + n).setModel("Kia Bongo").setExpeditor(expeditor), c);
            Warehouse car = save(warehouses, new Warehouse().setType(WarehouseType.VEHICLE).setName("Машина").setVehicle(v), c);
            Region region = save(regions, new Region().setName("Регион " + n), c);
            Route route = save(routes, new Route().setRegion(region).setName("Маршрут " + n).setAgent(agent).setDaysMask(127), c);
            Product p = save(products, new Product().setName("Печенье " + n).setCategory("Печенье").setPerBox(10), c);
            Outlet o = save(outlets, new Outlet().setName("Магазин " + n).setPriceType(wholesale).setCreditLimit(100_000)
                    .setPaymentDays(7).setCreatedAt(today()), c);
            save(routeOutlets, new RouteOutlet().setRoute(route).setOutlet(o).setPosition(0), c);
            return new World(c, operator, agent, expeditor, route, wholesale, p, o, v, main, defect, car);
        });
    }

    /** Ещё один сотрудник компании. */
    public Employee person(World w, String name, Role role) {
        return root(() -> person(w.company(), name, role));
    }

    /** Пароль для входа; mustChange — временный, при входе сначала сменить. */
    public void password(Employee e, String password, boolean mustChange) {
        jdbc.update("update users set password_hash = ?, must_change_password = ?, active = true where id = ?",
                encoder.encode(password), mustChange, e.getId());
    }

    /** Владелец (один на базу): нет — создаётся; пароль задаётся заново. Возвращает телефон для входа. */
    public String owner(String password) {
        List<String> phones = jdbc.queryForList("select phone from users where role = 'SUPER_ADMIN'", String.class);
        String phone = phones.isEmpty() ? "+77000000000" : phones.get(0);
        if (phones.isEmpty()) {
            jdbc.update("insert into users (name, role, phone, must_change_password, created_at) values ('Владелец', 'SUPER_ADMIN', ?, false, ?)",
                    phone, LocalDateTime.now(clock));
        }
        jdbc.update("update users set password_hash = ?, must_change_password = false, active = true where phone = ?",
                encoder.encode(password), phone);
        return phone;
    }

    private Employee person(Company c, String name, Role role) {
        return save(employees, new Employee().setName(name).setRole(role)
                .setPhone("+77" + String.format("%09d", SEQ.getAndIncrement())).setCreatedAt(LocalDateTime.now(clock)), c);
    }

    private static <T extends CompanyEntity> T save(org.springframework.data.repository.CrudRepository<T, Long> repo, T e, Company c) {
        e.setCompany(c);
        return repo.save(e);
    }

    public void openingDebt(World w, long amount, LocalDate asOf) {
        root(() -> save(openingDebts, new OutletOpeningDebt().setOutlet(w.outlet()).setAmount(amount).setAsOf(asOf), w.company()));
    }

    /** Ещё один магазин компании — на новом маршруте агента agent в новом регионе (филиале). */
    public Outlet outletInNewRegion(World w, Employee agent) {
        return root(() -> {
            long n = SEQ.getAndIncrement();
            Region region = save(regions, new Region().setName("Регион " + n), w.company());
            Route route = save(routes, new Route().setRegion(region).setName("Маршрут " + n).setAgent(agent).setDaysMask(127), w.company());
            Outlet o = save(outlets, new Outlet().setName("Магазин " + n).setPriceType(w.wholesale()).setCreditLimit(100_000)
                    .setPaymentDays(7).setCreatedAt(today()), w.company());
            save(routeOutlets, new RouteOutlet().setRoute(route).setOutlet(o).setPosition(0), w.company());
            return o;
        });
    }

    /** Заказ на одну строку: qty штук товара по price. */
    public Order order(World w, LocalDate delivery, PaymentMethod payment, int qty, long price) {
        return order(w, w.outlet(), w.agent(), delivery, payment, qty, price);
    }

    /** Заказ магазина outlet от агента agent. */
    public Order order(World w, Outlet outlet, Employee agent, LocalDate delivery, PaymentMethod payment, int qty, long price) {
        return root(() -> {
            Order o = new Order().setNumber("Т-" + SEQ.getAndIncrement()).setOutlet(outlet).setAgent(agent)
                    .setCreatedAt(LocalDateTime.now(clock)).setDeliveryDate(delivery).setStatus(OrderStatus.ACCEPTED).setPayment(payment);
            o.setCompany(w.company());
            o.addLine(new OrderLine().setProduct(w.product()).setQty(qty).setPrice(price));
            return orders.save(o);
        });
    }

    /** Выдача заказа: delivered штук (меньше заказанного — частично), без движения товара. */
    public void delivered(World w, Order order, Trip trip, int delivered, LocalDateTime at) {
        root(() -> {
            Order o = orders.findById(order.getId()).orElseThrow();
            OrderLine l = o.getLines().get(0);
            Delivery d = new Delivery().setOrder(o).setTrip(trip).setDeliveredAt(at).setExpeditor(w.expeditor())
                    .setStatus(delivered < l.getQty() ? DeliveryStatus.PARTIAL : DeliveryStatus.DELIVERED);
            d.setCompany(w.company());
            d.addItem(new DeliveryItem().setProduct(l.getProduct()).setQty(delivered).setPrice(l.getNetPrice()));
            deliveries.save(d);
            o.setStatus(delivered < l.getQty() ? OrderStatus.PARTIAL : OrderStatus.DELIVERED);
            return o;
        });
    }

    public void payment(World w, Order order, Trip trip, PaymentMethod method, long amount, LocalDateTime at) {
        root(() -> save(payments, new Payment().setOutlet(w.outlet()).setOrder(order).setTrip(trip).setMethod(method)
                .setAmount(amount).setAt(at).setReceivedBy(w.expeditor()), w.company()));
    }

    public ProductReturn productReturn(World w, Trip trip, int qty, long price, LocalDate date) {
        return root(() -> {
            ProductReturn r = new ProductReturn().setOutlet(w.outlet()).setTrip(trip).setDate(date)
                    .setCreatedAt(date.atTime(12, 0)).setReceivedBy(w.expeditor());
            r.setCompany(w.company());
            r.addLine(new ReturnLine().setProduct(w.product()).setQty(qty).setPrice(price).setReason(ReturnReason.DEFECT));
            return returns.save(r);
        });
    }

    /** Рейс сегодня с заказами по порядку; товар заказов загружен в машину с основного склада. */
    public Trip trip(World w, TripStatus status, Order... list) {
        return root(() -> {
            Trip t = save(trips, new Trip().setNumber("Р-" + SEQ.getAndIncrement()).setDate(today()).setExpeditor(w.expeditor())
                    .setVehicle(w.vehicle()).setStatus(status).setStartedAt(today().atTime(8, 0)), w.company());
            int pos = 0;
            for (Order o : list) {
                save(tripOrders, new TripOrder().setTrip(t).setOrder(o).setPosition(pos++), w.company());
                Order managed = orders.findById(o.getId()).orElseThrow();
                managed.setStatus(OrderStatus.IN_TRIP);
                for (OrderLine l : managed.getLines())
                    stock.move(l.getProduct(), l.getQty(), w.main(), w.car(), MovementReason.LOAD, null, null, m -> m.setTrip(t));
            }
            return t;
        });
    }

    /** Товар на склад: qty штук на основной склад компании. */
    public void stockIn(World w, int qty) {
        root(() -> stock.move(w.product(), qty, null, w.main(), MovementReason.ADJUST, Actor.system("Тест"), null, null));
    }

    /** Товар из магазина в машину (возврат негодного), как сделал бы экспедитор. */
    public void returnToCar(World w, Trip trip, ProductReturn r) {
        root(() -> {
            for (ReturnLine l : r.getLines())
                stock.move(l.getProduct(), l.getQty(), null, w.car(), MovementReason.RETURN, null, null, m -> m.setTrip(trip));
            return null;
        });
    }

    /** Выданное ушло из машины в магазин. */
    public void deliveredFromCar(World w, Trip trip, int qty) {
        root(() -> stock.move(w.product(), qty, w.car(), null, MovementReason.DELIVERY, null, null, m -> m.setTrip(trip)));
    }

    public void setTripStatus(Trip trip, TripStatus status) {
        root(() -> {
            trips.findById(trip.getId()).orElseThrow().setStatus(status);
            return null;
        });
    }

    public int balance(Warehouse w, Product p) {
        return root(() -> stock.rows(w.getCompanyId()).stream().filter(r -> r.product().getId().equals(p.getId())).findFirst()
                .map(r -> switch (w.getType()) {
                    case MAIN -> r.main();
                    case VEHICLE -> r.inVehicles();
                    case DEFECT -> r.defect();
                }).orElse(0));
    }
}
