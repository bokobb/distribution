package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;

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
    private final Clock clock;

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
