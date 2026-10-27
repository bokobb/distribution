package com.confectionery.distribution.domain;

import jakarta.persistence.Column;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.MappedSuperclass;
import lombok.Getter;
import org.hibernate.annotations.TenantId;

/**
 * Запись одной компании. companyId — «арендатор» Hibernate: он сам добавляет условие по компании во
 * все запросы (и в поиск по id) и сам заполняет его при сохранении — см. tenant/TenantResolver.
 * Чужую компанию записать нельзя: Hibernate откажет, а база не примет ссылку на чужую запись.
 */
@MappedSuperclass
@Getter
public abstract class CompanyEntity extends BaseEntity {

    @TenantId
    @Column(name = "company_id", updatable = false)
    private Long companyId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "company_id", insertable = false, updatable = false)
    private Company company;

    public void setCompany(Company company) {
        this.company = company;
        this.companyId = company == null ? null : company.getId();
    }
}
