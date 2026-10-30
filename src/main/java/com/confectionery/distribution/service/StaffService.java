package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import com.confectionery.distribution.security.MobileAccounts;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;

/**
 * Сотрудники компаний и машины. Владелец (без компании) в списки сотрудников не входит и через эту
 * форму не меняется. Новому сотруднику и при сбросе выдаётся временный пароль ({@link IssuedPassword}).
 */
@Service
@RequiredArgsConstructor
public class StaffService {

    private final EmployeeRepository employees;
    private final VehicleRepository vehicles;
    private final OutletRepository outlets;
    private final WarehouseRepository warehouses;
    private final CompanyRepository companies;
    private final PasswordEncoder encoder;
    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final MobileAccounts mobile;

    /** Сотрудники компании (с закреплёнными машинами); companyId = null — все видимые. */
    public List<Employee> employees(Long companyId) {
        List<Employee> list = employees.findByCompanyIdIsNotNullOrderByNameAsc().stream()
                .filter(e -> companyId == null || companyId.equals(e.getCompanyId())).toList();
        for (Vehicle v : vehicles.findAllByOrderByPlateAsc()) {
            if (v.getExpeditor() == null) continue;
            list.stream().filter(e -> e.getId().equals(v.getExpeditor().getId())).findFirst().ifPresent(e -> e.setVehicle(v));
        }
        return list;
    }

    public List<Employee> staff(Long companyId, Role role) {
        return employees(companyId).stream().filter(e -> e.getRole() == role).toList();
    }

    public List<Vehicle> vehicles(Long companyId) {
        return vehicles.findAllByOrderByPlateAsc().stream()
                .filter(v -> companyId == null || companyId.equals(v.getCompanyId()))
                .sorted(Comparator.comparing(Vehicle::getCompanyId).thenComparing(Vehicle::getPlate)).toList();
    }

    /** Сотрудник компании (с машиной, если экспедитор); владельца эта страница не открывает. */
    public Employee get(Long id) {
        Employee e = employees.findById(id).filter(x -> x.getRole() != Role.SUPER_ADMIN).orElseThrow(NotFoundException::new);
        vehicles.findAllByOrderByPlateAsc().stream()
                .filter(v -> v.getExpeditor() != null && v.getExpeditor().getId().equals(id)).findFirst().ifPresent(e::setVehicle);
        return e;
    }

    public Vehicle vehicle(Long id) {
        return vehicles.findById(id).orElseThrow(NotFoundException::new);
    }

    // ------------------------------------------------------------------ сотрудники

    /** Новый сотрудник компании companyId (у владельца в «Все компании» её нет — ошибка). */
    @Transactional
    public IssuedPassword create(EmployeeForm f, Long companyId) {
        if (companyId == null) throw new FormException("Выберите компанию в шапке: сотрудник добавляется в одну компанию");
        return create(companies.getReferenceById(companyId), f.getName(), f.getRole(), f.getPhone(), f.getLogin());
    }

    /** Создать сотрудника с временным паролем: и из формы, и директора новой компании. */
    @Transactional
    public IssuedPassword create(Company company, String rawName, Role role, String rawPhone, String rawLogin) {
        String name = Forms.required(rawName, "ФИО", 200);
        checkRole(role);
        String phone = phone(rawPhone, company.getId(), null);
        String login = login(rawLogin, company.getId(), null);
        String password = IssuedPassword.generate();
        Employee e = new Employee().setName(name).setRole(role).setPhone(phone).setLogin(login)
                .setPasswordHash(encoder.encode(password)).setMustChangePassword(true).setCreatedAt(LocalDateTime.now(clock));
        e.setCompany(company);
        employees.save(e);
        return new IssuedPassword(name, phone, password);
    }

    /** Изменить ФИО, роль, телефон, логин. Свою роль не поменять — чтобы не закрыть себе вход. */
    /** Версия приложения у каждого сотрудника — из последней записи журнала приложения: id → «1.0.6». */
    public Map<Long, String> appVersions() {
        Map<Long, String> out = new java.util.HashMap<>();
        jdbc.query("select distinct on (user_id) user_id, app_version from app_events where app_version is not null and app_version <> '' order by user_id, event_at desc",
                rs -> {
                    out.put(rs.getLong(1), rs.getString(2));
                });
        return out;
    }

    /** Сравнение версий «1.0.10» > «1.0.9» по числам. */
    public static int compareVersions(String a, String b) {
        String[] x = a.split("\\D+"), y = b.split("\\D+");
        for (int i = 0; i < Math.max(x.length, y.length); i++) {
            int p = i < x.length && !x[i].isEmpty() ? Integer.parseInt(x[i]) : 0, q = i < y.length && !y[i].isEmpty() ? Integer.parseInt(y[i]) : 0;
            if (p != q) return Integer.compare(p, q);
        }
        return 0;
    }

    /** Сколько магазинов закреплено за каждым торговым: id торгового → магазинов (без закрытых). */
    public Map<Long, Long> outletCounts() {
        return outlets.findAllByOrderByNameAsc().stream()
                .filter(o -> o.getAgent() != null && o.getStatus() != OutletStatus.CLOSED)
                .collect(java.util.stream.Collectors.groupingBy(o -> o.getAgent().getId(), java.util.stream.Collectors.counting()));
    }

    @Transactional
    public Employee update(EmployeeForm f, Long meId) {
        Employee e = get(f.getId());
        String name = Forms.required(f.getName(), "ФИО", 200);
        checkRole(f.getRole());
        if (e.getRole() != f.getRole()) {
            if (e.getId().equals(meId)) throw new FormException("Свою роль поменять нельзя — попросите другого директора или владельца");
            if (e.getRole() == Role.AGENT) {
                long own = outlets.findAllByOrderByNameAsc().stream()
                        .filter(o -> o.getAgent() != null && o.getAgent().getId().equals(e.getId())).count();
                if (own > 0) throw new FormException("За торговым закреплено магазинов: " + own + ". Сначала закрепите их за другим торговым");
            }
            if (e.getRole() == Role.EXPEDITOR && e.getVehicle() != null)
                throw new FormException("За экспедитором машина " + e.getVehicle().getPlate() + ". Сначала открепите её");
        }
        String phone = phone(f.getPhone(), e.getCompanyId(), e.getId());
        String login = login(f.getLogin(), e.getCompanyId(), e.getId());
        if (e.getRole() != f.getRole()) mobile.revokeAll(e.getId());
        return e.setName(name).setRole(f.getRole()).setPhone(phone).setLogin(login);
    }

    /** Новый временный пароль; старый перестаёт работать, вход в приложении на телефонах закрывается. */
    @Transactional
    public IssuedPassword resetPassword(Long id) {
        Employee e = get(id);
        String password = IssuedPassword.generate();
        e.setPasswordHash(encoder.encode(password)).setMustChangePassword(true);
        mobile.revokeAll(e.getId());
        return new IssuedPassword(e.getName(), e.getPhone(), password);
    }

    /** Отключённый сотрудник не входит ни в админку, ни в приложение (вход на телефонах закрывается); записи о нём остаются. */
    @Transactional
    public Employee setActive(Long id, boolean active, Long meId) {
        Employee e = get(id);
        if (!active && e.getId().equals(meId)) throw new FormException("Себя отключить нельзя");
        if (!active) mobile.revokeAll(e.getId());
        return e.setActive(active);
    }

    private static void checkRole(Role role) {
        if (role == null) throw new FormException("Выберите роль");
        if (role == Role.SUPER_ADMIN) throw new FormException("Роль «Владелец» не выдаётся");
    }

    /** Телефон для входа: +7 и 10 цифр, один на всю систему. */
    private String phone(String raw, Long companyId, Long exceptId) {
        String p = Phones.normalize(raw);
        if (p == null) throw new FormException("Телефон — +7 и 10 цифр, например +7 701 123 45 67");
        taken("phone", p, companyId, exceptId, "Этот телефон");
        return p;
    }

    /** Логин — по желанию: латиница, цифры, точка, дефис; хотя бы одна буква, чтобы не путать с телефоном. */
    private String login(String raw, Long companyId, Long exceptId) {
        String l = Forms.text(raw, "Логин", 64);
        if (l == null) return null;
        l = l.toLowerCase(Locale.ROOT);
        if (!l.matches("(?=.*[a-z])[a-z0-9._-]{3,64}"))
            throw new FormException("Логин — от 3 знаков: латинские буквы, цифры, точка, дефис, подчёркивание");
        taken("login", l, companyId, exceptId, "Этот логин");
        return l;
    }

    /**
     * Телефон и логин уникальны во всей системе, а фильтр компании прячет чужих сотрудников — поэтому
     * проверка идёт мимо него, прямым запросом. Имя из чужой компании не показываем.
     */
    private void taken(String column, String value, Long companyId, Long exceptId, String what) {
        List<Object[]> rows = jdbc.query("select company_id, name from users where " + column + " = ? and id <> ?",
                (rs, n) -> new Object[]{rs.getObject(1, Long.class), rs.getString(2)}, value, exceptId == null ? -1L : exceptId);
        if (rows.isEmpty()) return;
        Object[] r = rows.get(0);
        throw new FormException(Objects.equals(r[0], companyId) ? what + " уже у сотрудника «" + r[1] + "»" : what + " уже занят в системе");
    }

    // ------------------------------------------------------------------ машины

    /** Новая машина получает свой склад: товар в рейсе числится на нём. */
    @Transactional
    public Vehicle saveVehicle(VehicleForm f, Long companyId) {
        Vehicle v = f.getId() == null ? null : vehicle(f.getId());
        Long cid = v != null ? v.getCompanyId() : companyId;
        if (cid == null) throw new FormException("Выберите компанию в шапке: машина добавляется в одну компанию");
        String plate = Forms.required(f.getPlate(), "Гос. номер", 20).toUpperCase(Locale.ROOT).replaceAll("\\s+", " ");
        String model = Forms.text(f.getModel(), "Модель", 100);
        Long selfId = v == null ? null : v.getId();
        if (vehicles(cid).stream().anyMatch(x -> x.getPlate().equalsIgnoreCase(plate) && !x.getId().equals(selfId)))
            throw new FormException("Машина " + plate + " уже есть");
        Employee expeditor = null;
        if (f.getExpeditorId() != null) {
            expeditor = employees.findById(f.getExpeditorId())
                    .filter(e -> cid.equals(e.getCompanyId()) && e.getRole() == Role.EXPEDITOR)
                    .orElseThrow(() -> new FormException("Экспедитор не найден"));
            Long expId = expeditor.getId();
            vehicles(cid).stream().filter(x -> x.getExpeditor() != null && x.getExpeditor().getId().equals(expId)
                    && !x.getId().equals(selfId)).findFirst().ifPresent(x -> {
                throw new FormException("За экспедитором уже машина " + x.getPlate() + ". Сначала открепите её");
            });
        }
        boolean created = v == null;
        if (created) {
            v = new Vehicle();
            v.setCompany(companies.getReferenceById(cid));
        }
        v = vehicles.save(v.setPlate(plate).setModel(model).setExpeditor(expeditor));
        Warehouse w = created ? new Warehouse().setType(WarehouseType.VEHICLE).setVehicle(v)
                : warehouses.findByVehicle(v).orElseThrow();
        if (created) w.setCompany(v.getCompany());
        warehouses.save(w.setName("Машина " + plate));
        return v;
    }

    /** Экспедиторы компании без машины (и закреплённый за этой машиной) — для выбора в форме. */
    public List<Employee> freeExpeditors(Long companyId, Long vehicleId) {
        return staff(companyId, Role.EXPEDITOR).stream()
                .filter(Employee::isActive)
                .filter(e -> e.getVehicle() == null || e.getVehicle().getId().equals(vehicleId)).toList();
    }
}
