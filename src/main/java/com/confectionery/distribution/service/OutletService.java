package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.file.Path;
import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/** Магазины компании: список с долгами, карточка, проверка новых, добавление и правка. */
@Service
@RequiredArgsConstructor
public class OutletService {

    private final OutletRepository outlets;
    private final OrderRepository orders;
    private final PaymentRepository payments;
    private final ProductReturnRepository returns;
    private final DebtService debts;
    private final RouteRepository routes;
    private final RouteOutletRepository routeOutlets;
    private final PriceTypeRepository priceTypes;
    private final CompanyRepository companies;
    private final EmployeeRepository employees;
    private final SettingsService settings;
    private final FileStore files;
    private final Clock clock;

    /**
     * Новый магазин с телефона агента; lat/lng — где агент его отметил (по GPS или вручную на карте). Тип цен агент
     * не выбирает — его ставит оператор; priceKind от старых версий приложения не читается.
     */
    public record AgentOutletIn(UUID uuid, Long routeId, String name, String legal, String bin, String owner,
                                String phone, String phone2, String address, String landmark, Double lat, Double lng) {
    }

    /** Все магазины (с долгами); companyId = null — все видимые. */
    public List<Outlet> list(Long companyId) {
        List<Outlet> list = outlets.findAllByOrderByNameAsc().stream()
                .filter(o -> companyId == null || companyId.equals(o.getCompanyId())).toList();
        debts.fill(list);
        return list;
    }

    public Outlet get(Long id) {
        Outlet o = outlets.findById(id).orElseThrow(NotFoundException::new);
        debts.fill(o);
        return o;
    }

    public List<Order> ordersOf(Outlet o) {
        return orders.findByOutletOrderByCreatedAtDesc(o);
    }

    public List<Payment> paymentsOf(Outlet o) {
        return payments.findByOutletOrderByAtDesc(o);
    }

    public List<ProductReturn> returnsOf(Outlet o) {
        return returns.findByOutletOrderByDateDesc(o);
    }

    /** Новый магазин от агента проверен — работает. */
    @Transactional
    public Outlet approve(Long id) {
        Outlet o = outlets.findById(id).orElseThrow(NotFoundException::new);
        if (o.getStatus() == OutletStatus.PENDING) o.setStatus(OutletStatus.ACTIVE);
        return o;
    }

    /**
     * Магазин от агента с телефона: «на проверке» у оператора (до проверки агент уже может в нём работать),
     * в конце обхода его маршрута; лимит долга — как у нового магазина в настройках компании; цены — оптовые, пока
     * оператор не поставит другой тип цен. Повтор с тем же uuid возвращает уже добавленный.
     */
    @Transactional
    public Outlet addByAgent(Long agentId, AgentOutletIn in) {
        if (in.uuid() == null) throw new FormException("Магазин без uuid — обновите приложение");
        Employee agent = employees.findById(agentId).orElseThrow(NotFoundException::new);
        Outlet was = outlets.findByUuid(in.uuid()).orElse(null);
        if (was != null) return was;
        String name = Forms.required(in.name(), "Название", 200);
        String phone = phone(Forms.required(in.phone(), "Телефон", 64), "Телефон");
        String phone2 = in.phone2() == null || in.phone2().isBlank() ? null : phone(in.phone2(), "Телефон 2");
        String bin = Forms.text(in.bin(), "БИН / ИИН", 20);
        if (bin != null && !bin.matches("\\d{12}")) throw new FormException("БИН / ИИН — 12 цифр");
        String address = Forms.text(in.address(), "Адрес", 300);
        String landmark = Forms.text(in.landmark(), "Ориентир", 300);
        if (address == null && landmark == null) throw new FormException("Укажите адрес или ориентир");
        Double lat = in.lat(), lng = in.lng();
        if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) lat = lng = null;
        PriceType priceType = priceTypes.findByCompanyIdAndCode(agent.getCompanyId(), PriceKind.WHOLESALE)
                .orElseThrow(() -> new FormException("В компании нет оптовых цен — обратитесь к оператору"));
        List<Route> mine = routes.findAllByOrderByNameAsc().stream()
                .filter(r -> r.isActive() && r.getAgent() != null && r.getAgent().getId().equals(agent.getId())).toList();
        Route route = mine.stream().filter(r -> r.getId().equals(in.routeId())).findFirst()
                .orElse(mine.isEmpty() ? null : mine.get(0));
        if (route == null) throw new FormException("У вас нет маршрута — магазин добавит оператор");

        Outlet o = new Outlet().setUuid(in.uuid()).setStatus(OutletStatus.PENDING).setCreatedAt(LocalDate.now(clock))
                .setCreatedBy(agent.getName()).setName(name).setLegal(Forms.text(in.legal(), "ИП / ТОО", 200)).setBin(bin)
                .setOwner(Forms.text(in.owner(), "Владелец", 200)).setPhone(phone).setPhone2(phone2).setAddress(address)
                .setLandmark(landmark).setLat(lat).setLng(lng).setPriceType(priceType)
                .setCreditLimit(settings.of(agent.getCompanyId()).getDefaultCreditLimit()).setPaymentDays(0);
        o.setCompany(agent.getCompany());
        o = outlets.save(o);
        placeOnRoute(o, route);
        return o;
    }

    /** Фото фасада к магазину на маршруте агента; повтор заменяет файл. */
    @Transactional
    public void facadeByAgent(Long agentId, UUID uuid, byte[] jpeg) {
        Outlet o = outlets.findByUuid(uuid).filter(x -> x.getAgent() != null && x.getAgent().getId().equals(agentId))
                .orElseThrow(NotFoundException::new);
        o.setFacadePhoto(files.savePhoto(o.getCompanyId(), "outlets", uuid, jpeg));
    }

    /** Файл фото фасада — для админки. */
    public Optional<Path> facadeFile(Outlet o) {
        return files.find(o.getFacadePhoto());
    }

    private static String phone(String raw, String field) {
        String p = Phones.normalize(raw);
        if (p == null) throw new FormException(field + " — +7 и 10 цифр, например +7 701 123 45 67");
        return Phones.format(p);
    }

    /**
     * Сохранить магазин из формы. Новый — в компанию companyId (у владельца в «Все компании» её нет —
     * тогда ошибка), сразу работает. Поля, которых нет в форме (второй телефон, ориентир, фото), не
     * трогаются. Маршрут и тип цен — только своей компании.
     */
    @Transactional
    public Outlet save(OutletForm f, Long companyId, String who) {
        Outlet o = f.getId() == null ? null : outlets.findById(f.getId()).orElseThrow(NotFoundException::new);
        Long cid = o != null ? o.getCompanyId() : companyId;
        if (cid == null) throw new FormException("Выберите компанию в шапке: магазин добавляется в одну компанию");

        String name = Forms.required(f.getName(), "Название", 200);
        String legal = Forms.text(f.getLegal(), "ИП / ТОО", 200);
        String bin = Forms.text(f.getBin(), "БИН / ИИН", 20);
        if (bin != null && !bin.matches("\\d{12}")) throw new FormException("БИН / ИИН — 12 цифр");
        String owner = Forms.text(f.getOwner(), "Владелец", 200);
        String phone = Forms.text(f.getPhone(), "Телефон", 64);
        if (phone != null) {
            String p = Phones.normalize(phone);
            if (p == null) throw new FormException("Телефон — +7 и 10 цифр, например +7 701 123 45 67");
            phone = Phones.format(p);
        }
        String address = Forms.text(f.getAddress(), "Адрес", 300);
        long limit = Forms.money(f.getCreditLimit(), "Лимит долга");
        int days = Forms.number(f.getPaymentDays(), "Отсрочка, дней", 0, 365);
        Double lat = Forms.coord(f.getLat(), "Широта", 90);
        Double lng = Forms.coord(f.getLng(), "Долгота", 180);
        if ((lat == null) != (lng == null)) throw new FormException("Укажите и широту, и долготу — или оставьте обе пустыми");
        PriceType priceType = f.getPriceTypeId() == null ? null : priceTypes.findById(f.getPriceTypeId())
                .filter(t -> cid.equals(t.getCompanyId())).orElse(null);
        if (priceType == null) throw new FormException("Выберите тип цен");
        Route route = f.getRouteId() == null ? null : routes.findById(f.getRouteId())
                .filter(r -> cid.equals(r.getCompanyId())).orElseThrow(() -> new FormException("Маршрут не найден"));

        if (o == null) {
            o = new Outlet().setStatus(OutletStatus.ACTIVE).setCreatedAt(LocalDate.now(clock)).setCreatedBy(who);
            o.setCompany(companies.getReferenceById(cid));
        }
        o.setName(name).setLegal(legal).setBin(bin).setOwner(owner).setPhone(phone).setAddress(address)
                .setCreditLimit(limit).setPaymentDays(days).setLat(lat).setLng(lng).setPriceType(priceType);
        o = outlets.save(o);
        placeOnRoute(o, route);
        return o;
    }

    /** Магазин — в конец обхода нового маршрута; null — снять с маршрута. Тот же маршрут — порядок не меняется. */
    private void placeOnRoute(Outlet o, Route route) {
        RouteOutlet link = routeOutlets.findByOutlet(o).orElse(null);
        if (route == null) {
            if (link != null) routeOutlets.delete(link);
            return;
        }
        if (link != null && link.getRoute().getId().equals(route.getId())) return;
        int position = routeOutlets.maxPosition(route) + 1;
        if (link == null) {
            link = new RouteOutlet().setOutlet(o);
            link.setCompany(o.getCompany());
        }
        routeOutlets.save(link.setRoute(route).setPosition(position));
    }
}
