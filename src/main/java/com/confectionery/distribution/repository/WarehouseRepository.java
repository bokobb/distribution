package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Vehicle;
import com.confectionery.distribution.domain.Warehouse;
import com.confectionery.distribution.domain.WarehouseType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface WarehouseRepository extends JpaRepository<Warehouse, Long> {
    Optional<Warehouse> findByCompanyIdAndType(Long companyId, WarehouseType type);

    Optional<Warehouse> findByVehicle(Vehicle vehicle);
}
