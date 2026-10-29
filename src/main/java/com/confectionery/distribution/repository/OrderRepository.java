package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Order;
import com.confectionery.distribution.domain.OrderStatus;
import com.confectionery.distribution.domain.Outlet;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface OrderRepository extends JpaRepository<Order, Long> {
    List<Order> findByDeliveryDate(LocalDate date);

    List<Order> findByDeliveryDateAfter(LocalDate date);

    List<Order> findByDeliveryDateGreaterThanEqual(LocalDate date);

    List<Order> findByStatusIn(Collection<OrderStatus> statuses);

    List<Order> findByCreatedAtGreaterThanEqualAndCreatedAtLessThan(LocalDateTime from, LocalDateTime to);

    List<Order> findByOutletOrderByCreatedAtDesc(Outlet outlet);

    Optional<Order> findByUuid(UUID uuid);

    /** Только id: заказ потом читается под блокировкой (lockAll) — свежим. */
    @Query("select o.id from Order o where o.uuid = :uuid")
    Optional<Long> idByUuid(UUID uuid);

    boolean existsByCompanyIdAndNumber(Long companyId, String number);

    List<Order> findByAgentIdAndCreatedAtGreaterThanEqualAndCreatedAtLessThanOrderByCreatedAtAsc(Long agentId,
                                                                                                LocalDateTime from,
                                                                                                LocalDateTime to);

    /** Заказы под изменение: двое отгружают одни и те же заказы — второй ждёт и видит их уже в рейсе. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select o from Order o where o.id in :ids order by o.id")
    List<Order> lockAll(Collection<Long> ids);
}
