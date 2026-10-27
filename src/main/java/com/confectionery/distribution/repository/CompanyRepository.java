package com.confectionery.distribution.repository;

import com.confectionery.distribution.domain.Company;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

/** Компании — не запись компании, фильтра нет: список отдаётся только владельцу (см. CompanyService). */
public interface CompanyRepository extends JpaRepository<Company, Long> {
    List<Company> findAllByOrderByIdAsc();
}
