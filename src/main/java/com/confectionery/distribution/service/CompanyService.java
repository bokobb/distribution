package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.repository.CompanyRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Компании. Таблица общая (без фильтра компании), поэтому список целиком отдаётся только владельцу,
 * остальным — их компания.
 */
@Service
@RequiredArgsConstructor
public class CompanyService {

    private final CompanyRepository companies;

    public List<Company> all() {
        return companies.findAllByOrderByIdAsc();
    }

    public Company get(Long id) {
        return id == null ? null : companies.findById(id).orElse(null);
    }

    /** Первая компания — та, что видна в режиме «Все компании» там, где у каждой своё (прайс, склад). */
    public Company first() {
        return all().stream().findFirst().orElse(null);
    }
}
