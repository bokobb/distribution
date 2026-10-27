package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.Outlet;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

public interface OrderRepository extends JpaRepository<Order, Long> {
    List<Order> findByDeliveryDate(LocalDate date);

    List<Order> findByDeliveryDateAfter(LocalDate date);

    List<Order> findByDeliveryDateGreaterThanEqual(LocalDate date);

    List<Order> findByStatusIn(Collection<OrderStatus> statuses);

    List<Order> findByCreatedAtGreaterThanEqualAndCreatedAtLessThan(LocalDateTime from, LocalDateTime to);

    List<Order> findByOutletOrderByCreatedAtDesc(Outlet outlet);
}
