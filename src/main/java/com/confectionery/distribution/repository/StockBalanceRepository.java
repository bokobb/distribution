package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Product;
import com.confectionery.distribution.domain.StockBalance;
import com.confectionery.distribution.domain.Warehouse;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.util.Optional;

public interface StockBalanceRepository extends JpaRepository<StockBalance, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<StockBalance> findByWarehouseAndProduct(Warehouse warehouse, Product product);
}
