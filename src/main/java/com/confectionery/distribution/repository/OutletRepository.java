package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.OutletStatus;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface OutletRepository extends JpaRepository<Outlet, Long> {
    List<Outlet> findAllByOrderByNameAsc();

    Optional<Outlet> findByUuid(UUID uuid);

    @EntityGraph(attributePaths = {"agent", "company"})
    List<Outlet> findByStatusOrderByIdAsc(OutletStatus status);
}
