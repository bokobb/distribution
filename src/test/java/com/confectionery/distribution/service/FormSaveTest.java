package com.confectionery.distribution.service;

import com.confectionery.distribution.TestData;
import com.confectionery.distribution.TestData.World;
import com.confectionery.distribution.TestcontainersConfiguration;
import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import com.confectionery.distribution.tenant.TenantContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Сохранение форм админки: компания, сотрудник, машина, магазин, настройки. */
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestData.class})
class FormSaveTest {

    private static final AtomicLong SEQ = new AtomicLong();

    @Autowired
    TestData data;
    @Autowired
    CompanyService companies;
    @Autowired
    StaffService staff;
    @Autowired
    OutletService outlets;
    @Autowired
    SettingsService settings;
    @Autowired
    EmployeeRepository employeeRepo;
    @Autowired
    WarehouseRepository warehouseRepo;
    @Autowired
    PriceTypeRepository priceTypeRepo;
    @Autowired
    CompanySettingsRepository settingsRepo;
    @Autowired
    CompanyRepository companyRepo;
    @Autowired
    OutletRepository outletRepo;
    @Autowired
    RouteOutletRepository routeOutletRepo;
    @Autowired
    PasswordEncoder encoder;
    @Autowired
    TransactionTemplate tx;

    /** Действие как сотрудник компании tenant (ROOT — владелец во «Все компании»), в своей транзакции. */
    private <T> T in(long tenant, Supplier<T> action) {
        return TenantContext.call(tenant, () -> tx.execute(s -> action.get()));
    }

    /** Телефон, как его вводят: «8 705 …», каждый раз новый. */
    private static String newPhone() {
        return "8 " + (7_055_500_000L + SEQ.incrementAndGet());
    }

    private static EmployeeForm employee(String name, Role role, String phone) {
        EmployeeForm f = new EmployeeForm();
        f.setName(name);
        f.setRole(role);
        f.setPhone(phone);
        return f;
    }

    // ------------------------------------------------------------------ компания

    @Test
    void новаяКомпанияСразуГотоваКРаботе() {
        CompanyForm f = new CompanyForm();
        f.setName("Склад-дилер В" + SEQ.incrementAndGet());
        f.setDirector("Ахмет Сериков");
        f.setPhone(newPhone());
        f.setCrmClient("  ТОО «Дилер В»  ");

        IssuedPassword p = in(TenantContext.ROOT, () -> companies.create(f));

        Company c = in(TenantContext.ROOT, () -> companies.all().stream().filter(x -> x.getName().equals(f.getName())).findFirst().orElseThrow());
        assertThat(c.getPhone()).isEqualTo(p.phone()).matches("\\+7\\d{10}");
        assertThat(c.getCrmClient()).isEqualTo("ТОО «Дилер В»");
        assertThat(c.isOwn()).isFalse();
        in(TenantContext.ROOT, () -> {
            assertThat(settingsRepo.findByCompanyId(c.getId())).isPresent();
            assertThat(priceTypeRepo.findByCompanyIdOrderByIdAsc(c.getId())).extracting(PriceType::getCode)
                    .containsExactly(PriceKind.WHOLESALE, PriceKind.RETAIL);
            assertThat(warehouseRepo.findByCompanyIdAndType(c.getId(), WarehouseType.MAIN)).isPresent();
            assertThat(warehouseRepo.findByCompanyIdAndType(c.getId(), WarehouseType.DEFECT)).isPresent();
            Employee d = employeeRepo.findByPhone(p.phone()).orElseThrow();
            assertThat(d.getRole()).isEqualTo(Role.DIRECTOR);
            assertThat(d.getCompanyId()).isEqualTo(c.getId());
            assertThat(d.isMustChangePassword()).isTrue();
            assertThat(encoder.matches(p.password(), d.getPasswordHash())).isTrue();
            return null;
        });
        assertThat(p.password()).hasSize(8);
    }

    @Test
    void компанияСЗанятымТелефономНеСоздаётсяИИмяЧужогоНеВидно() {
        World w = data.world("Т");
        CompanyForm f = new CompanyForm();
        f.setName("Склад-дилер Г" + SEQ.incrementAndGet());
        f.setDirector("Гаухар Ли");
        f.setPhone(w.operator().getPhone());

        assertThatThrownBy(() -> in(TenantContext.ROOT, () -> companies.create(f)))
                .isInstanceOf(FormException.class).hasMessage("Этот телефон уже занят в системе");
        assertThat(in(TenantContext.ROOT, () -> companies.all()))
                .noneMatch(c -> c.getName().equals(f.getName()));
    }

    // ------------------------------------------------------------------ сотрудник

    @Test
    void сотрудник_телефонПриводитсяКВидуВхода_занятыйЧужимНеВыдаётИмя() {
        World a = data.world("А");
        World b = data.world("Б");
        String typed = newPhone();
        IssuedPassword p = in(a.id(), () -> staff.create(employee("Нурлан Агентов", Role.AGENT, typed), a.id()));
        assertThat(p.phone()).isEqualTo("+7" + typed.replaceAll("\\D", "").substring(1));

        EmployeeForm again = employee("Другой", Role.AGENT, p.phone());
        assertThatThrownBy(() -> in(b.id(), () -> staff.create(again, b.id())))
                .isInstanceOf(FormException.class).hasMessage("Этот телефон уже занят в системе");
        assertThatThrownBy(() -> in(a.id(), () -> staff.create(again, a.id())))
                .isInstanceOf(FormException.class).hasMessage("Этот телефон уже у сотрудника «Нурлан Агентов»");
        assertThatThrownBy(() -> in(a.id(), () -> staff.create(employee("Х", Role.AGENT, "12345"), a.id())))
                .isInstanceOf(FormException.class).hasMessageStartingWith("Телефон — +7 и 10 цифр");
    }

    @Test
    void рольВладельцаНеВыдаётся_чужойСотрудникНеМеняется() {
        World a = data.world("А");
        World b = data.world("Б");
        assertThatThrownBy(() -> in(a.id(), () -> staff.create(employee("Хитрый", Role.SUPER_ADMIN, newPhone()), a.id())))
                .isInstanceOf(FormException.class).hasMessage("Роль «Владелец» не выдаётся");

        EmployeeForm foreign = EmployeeForm.of(b.operator());
        foreign.setName("Переименован");
        assertThatThrownBy(() -> in(a.id(), () -> staff.update(foreign, null))).isInstanceOf(NotFoundException.class);
        assertThatThrownBy(() -> in(a.id(), () -> staff.resetPassword(b.operator().getId()))).isInstanceOf(NotFoundException.class);
        assertThatThrownBy(() -> in(a.id(), () -> staff.setActive(b.operator().getId(), false, null))).isInstanceOf(NotFoundException.class);
        Employee still = in(TenantContext.ROOT, () -> employeeRepo.findById(b.operator().getId()).orElseThrow());
        assertThat(still.getName()).isEqualTo(b.operator().getName());
        assertThat(still.isActive()).isTrue();
    }

    @Test
    void рольНеМеняетсяУСебяИУАгентаСМаршрутом() {
        World w = data.world("Р");
        EmployeeForm self = EmployeeForm.of(w.operator());
        self.setRole(Role.STOREKEEPER);
        assertThatThrownBy(() -> in(w.id(), () -> staff.update(self, w.operator().getId())))
                .isInstanceOf(FormException.class).hasMessageStartingWith("Свою роль поменять нельзя");
        assertThatThrownBy(() -> in(w.id(), () -> staff.setActive(w.operator().getId(), false, w.operator().getId())))
                .isInstanceOf(FormException.class).hasMessage("Себя отключить нельзя");

        EmployeeForm agent = EmployeeForm.of(w.agent());
        agent.setRole(Role.OPERATOR);
        assertThatThrownBy(() -> in(w.id(), () -> staff.update(agent, null)))
                .isInstanceOf(FormException.class).hasMessageStartingWith("У агента маршруты: " + w.route().getName());
    }

    @Test
    void новыйПарольЗаменяетСтарый() {
        World w = data.world("П");
        IssuedPassword first = in(w.id(), () -> staff.create(employee("Кладовщик Петров", Role.STOREKEEPER, newPhone()), w.id()));
        Employee e = in(w.id(), () -> employeeRepo.findByPhone(first.phone()).orElseThrow());
        IssuedPassword second = in(w.id(), () -> staff.resetPassword(e.getId()));
        String hash = in(w.id(), () -> employeeRepo.findById(e.getId()).orElseThrow().getPasswordHash());
        assertThat(encoder.matches(second.password(), hash)).isTrue();
        assertThat(encoder.matches(first.password(), hash)).isFalse();
    }

    // ------------------------------------------------------------------ машина

    @Test
    void машинаПолучаетСвойСклад_экспедиторТолькоСвойИСвободный() {
        World a = data.world("А");
        World b = data.world("Б");
        IssuedPassword p = in(a.id(), () -> staff.create(employee("Экспедитор Новый", Role.EXPEDITOR, newPhone()), a.id()));
        Long freeId = in(a.id(), () -> employeeRepo.findByPhone(p.phone()).orElseThrow().getId());
        VehicleForm f = new VehicleForm();
        f.setPlate("  777 abc  02 ");
        f.setModel("Hyundai Porter");

        f.setExpeditorId(b.expeditor().getId());
        assertThatThrownBy(() -> in(a.id(), () -> staff.saveVehicle(f, a.id())))
                .isInstanceOf(FormException.class).hasMessage("Экспедитор не найден");
        f.setExpeditorId(a.expeditor().getId());
        assertThatThrownBy(() -> in(a.id(), () -> staff.saveVehicle(f, a.id())))
                .isInstanceOf(FormException.class).hasMessageStartingWith("За экспедитором уже машина " + a.vehicle().getPlate());

        f.setExpeditorId(freeId);
        Vehicle v = in(a.id(), () -> staff.saveVehicle(f, a.id()));
        assertThat(v.getPlate()).isEqualTo("777 ABC 02");
        Warehouse car = in(a.id(), () -> warehouseRepo.findByVehicle(v).orElseThrow());
        assertThat(car.getType()).isEqualTo(WarehouseType.VEHICLE);
        assertThat(car.getName()).isEqualTo("Машина 777 ABC 02");

        VehicleForm twin = new VehicleForm();
        twin.setPlate("777 ABC 02");
        assertThatThrownBy(() -> in(a.id(), () -> staff.saveVehicle(twin, a.id())))
                .isInstanceOf(FormException.class).hasMessage("Машина 777 ABC 02 уже есть");
    }

    // ------------------------------------------------------------------ магазин

    @Test
    void новыйМагазинВстаётВКонецМаршрута() {
        World w = data.world("М");
        OutletForm f = new OutletForm();
        f.setName("Магазин у дороги");
        f.setPhone("8 701 123 45 67");
        f.setPriceTypeId(w.wholesale().getId());
        f.setRouteId(w.route().getId());
        f.setCreditLimit("80 000");
        f.setPaymentDays("10");

        Outlet o = in(w.id(), () -> outlets.save(f, w.id(), "Директор Тестов"));

        in(w.id(), () -> {
            Outlet saved = outletRepo.findById(o.getId()).orElseThrow();
            assertThat(saved.getCompanyId()).isEqualTo(w.id());
            assertThat(saved.getStatus()).isEqualTo(OutletStatus.ACTIVE);
            assertThat(saved.getPhone()).isEqualTo("+7 701 123 45 67");
            assertThat(saved.getCreditLimit()).isEqualTo(80_000);
            assertThat(saved.getCreatedBy()).isEqualTo("Директор Тестов");
            assertThat(routeOutletRepo.findByOutlet(saved).orElseThrow().getPosition()).isEqualTo(1);
            return null;
        });
        assertThatThrownBy(() -> in(TenantContext.ROOT, () -> outlets.save(f, null, "Владелец")))
                .isInstanceOf(FormException.class).hasMessageStartingWith("Выберите компанию в шапке");
    }

    @Test
    void правкаМагазина_маршрутТолькоСвой_поляВнеФормыОстаются() {
        World a = data.world("А");
        World b = data.world("Б");
        in(TenantContext.ROOT, () -> outletRepo.findById(a.outlet().getId()).orElseThrow()
                .setPhone2("+7 700 111 22 33").setLandmark("напротив мечети"));
        OutletForm f = in(a.id(), () -> OutletForm.of(outlets.get(a.outlet().getId())));
        f.setName("Магазин «Новый»");
        f.setCreditLimit("150 000 ₸");

        f.setRouteId(b.route().getId());
        assertThatThrownBy(() -> in(a.id(), () -> outlets.save(f, a.id(), "Тест")))
                .isInstanceOf(FormException.class).hasMessage("Маршрут не найден");
        f.setRouteId(null);
        f.setBin("123");
        assertThatThrownBy(() -> in(a.id(), () -> outlets.save(f, a.id(), "Тест")))
                .isInstanceOf(FormException.class).hasMessage("БИН / ИИН — 12 цифр");
        f.setBin("");
        in(a.id(), () -> outlets.save(f, a.id(), "Тест"));

        in(a.id(), () -> {
            Outlet o = outletRepo.findById(a.outlet().getId()).orElseThrow();
            assertThat(o.getName()).isEqualTo("Магазин «Новый»");
            assertThat(o.getCreditLimit()).isEqualTo(150_000);
            assertThat(o.getBin()).isNull();
            assertThat(o.getPhone2()).isEqualTo("+7 700 111 22 33");
            assertThat(o.getLandmark()).isEqualTo("напротив мечети");
            assertThat(routeOutletRepo.findByOutlet(o)).isEmpty();
            return null;
        });
    }

    // ------------------------------------------------------------------ настройки

    @Test
    void настройки_проверкаДиапазона_клиентCrmМеняетТолькоВладелец() {
        World w = data.world("Н");
        SettingsForm f = in(w.id(), () -> SettingsForm.of(settings.of(w.id()), null));
        f.setVisitRadius("5");
        assertThatThrownBy(() -> in(w.id(), () -> settings.save(w.id(), f, false)))
                .isInstanceOf(FormException.class).hasMessage("«Радиус, метров» — число от 10 до 5000");
        Optional<CompanySettings> none = in(w.id(), () -> settingsRepo.findByCompanyId(w.id()));
        assertThat(none).isEmpty();

        f.setVisitRadius("300");
        f.setKaspi(false);
        f.setCashTolerance("1 000");
        f.setCrmClient("ТОО «Чужой»");
        in(w.id(), () -> settings.save(w.id(), f, false));
        CompanySettings st = in(w.id(), () -> settingsRepo.findByCompanyId(w.id()).orElseThrow());
        assertThat(st.getVisitRadius()).isEqualTo(300);
        assertThat(st.isAcceptKaspi()).isFalse();
        assertThat(st.getCashTolerance()).isEqualTo(1_000);
        assertThat(in(w.id(), () -> companyRepo.findById(w.id()).orElseThrow().getCrmClient())).isNull();

        in(TenantContext.ROOT, () -> settings.save(w.id(), f, true));
        assertThat(in(w.id(), () -> companyRepo.findById(w.id()).orElseThrow().getCrmClient())).isEqualTo("ТОО «Чужой»");
        List<CompanySettings> rows = in(TenantContext.ROOT, () -> settingsRepo.findAll().stream()
                .filter(s -> s.getCompanyId().equals(w.id())).toList());
        assertThat(rows).hasSize(1);
    }
}
