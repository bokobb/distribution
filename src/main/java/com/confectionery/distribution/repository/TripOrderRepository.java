package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.TripOrder;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TripOrderRepository extends JpaRepository<TripOrder, Long> {
}
