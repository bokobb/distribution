package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.Route;
import com.confectionery.distribution.domain.RouteOutlet;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;

public interface RouteOutletRepository extends JpaRepository<RouteOutlet, Long> {
    Optional<RouteOutlet> findByOutlet(Outlet outlet);

    @Query("select coalesce(max(ro.position), -1) from RouteOutlet ro where ro.route = ?1")
    int maxPosition(Route route);
}
