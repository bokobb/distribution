package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Delivery;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface DeliveryRepository extends JpaRepository<Delivery, Long> {
    List<Delivery> findByDeliveredAtGreaterThanEqualAndDeliveredAtLessThan(LocalDateTime from, LocalDateTime to);
}
