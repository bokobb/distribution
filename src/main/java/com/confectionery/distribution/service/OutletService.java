package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/** Магазины компании: список с долгами, карточка, проверка новых. */
@Service
@RequiredArgsConstructor
public class OutletService {

    private final OutletRepository outlets;
    private final OrderRepository orders;
    private final PaymentRepository payments;
    private final ProductReturnRepository returns;
    private final DebtService debts;

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
}
