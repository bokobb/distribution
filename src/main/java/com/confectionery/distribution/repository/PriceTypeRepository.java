package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.PriceKind;
import com.confectionery.distribution.domain.PriceType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface PriceTypeRepository extends JpaRepository<PriceType, Long> {
    List<PriceType> findByCompanyIdOrderByIdAsc(Long companyId);

    Optional<PriceType> findByCompanyIdAndCode(Long companyId, PriceKind code);
}
