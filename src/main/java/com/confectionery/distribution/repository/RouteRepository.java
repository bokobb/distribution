package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Route;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface RouteRepository extends JpaRepository<Route, Long> {
    List<Route> findAllByOrderByNameAsc();
}
