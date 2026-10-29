package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Region;
import com.confectionery.distribution.repository.RegionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

/** Районы (филиалы) — для фильтров и закрепления магазинов. */
@Service
@RequiredArgsConstructor
public class RegionService {

    private final RegionRepository regions;

    public List<Region> regions() {
        return regions.findAllByOrderByNameAsc();
    }
}
