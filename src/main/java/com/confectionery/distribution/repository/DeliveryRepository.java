package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Delivery;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface DeliveryRepository extends JpaRepository<Delivery, Long> {
    List<Delivery> findByDeliveredAtGreaterThanEqualAndDeliveredAtLessThan(LocalDateTime from, LocalDateTime to);

    Optional<Delivery> findByUuid(UUID uuid);
}
