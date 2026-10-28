package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.Payment;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface PaymentRepository extends JpaRepository<Payment, Long> {
    List<Payment> findByOutletOrderByAtDesc(Outlet outlet);

    Optional<Payment> findByUuid(UUID uuid);
}
