package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Price;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;

public interface PriceRepository extends JpaRepository<Price, Long> {
    List<Price> findByValidFromLessThanEqualOrderByValidFromAsc(LocalDate date);
}
