package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Outlet;
import com.confectionery.distribution.domain.ProductReturn;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;

public interface ProductReturnRepository extends JpaRepository<ProductReturn, Long> {
    List<ProductReturn> findByOutletOrderByDateDesc(Outlet outlet);

    List<ProductReturn> findByDate(LocalDate date);
}
