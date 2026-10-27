package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Region;
import com.confectionery.distribution.domain.Route;
import com.confectionery.distribution.repository.RegionRepository;
import com.confectionery.distribution.repository.RouteRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

/** Регионы и маршруты агентов. */
@Service
@RequiredArgsConstructor
public class RouteService {

    private final RegionRepository regions;
    private final RouteRepository routes;

    public List<Region> regions() {
        return regions.findAllByOrderByNameAsc();
    }

    public List<Route> routes() {
        return routes.findAllByOrderByNameAsc();
    }
}
