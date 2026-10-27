package com.confectionery.distribution.tenant;

import org.hibernate.cfg.MultiTenancySettings;
import org.hibernate.context.spi.CurrentTenantIdentifierResolver;
import org.springframework.boot.hibernate.autoconfigure.HibernatePropertiesCustomizer;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * Компания для Hibernate (@TenantId в CompanyEntity): берётся из {@link TenantContext}. ROOT — без
 * фильтра (владелец, «Все компании»); если компании нет — NONE, и запрос ничего не найдёт.
 */
@Component
public class TenantResolver implements CurrentTenantIdentifierResolver<Long>, HibernatePropertiesCustomizer {

    @Override
    public Long resolveCurrentTenantIdentifier() {
        Long t = TenantContext.current();
        return t == null ? TenantContext.NONE : t;
    }

    @Override
    public boolean validateExistingCurrentSessions() {
        return false;
    }

    @Override
    public boolean isRoot(Long tenant) {
        return tenant != null && tenant == TenantContext.ROOT;
    }

    @Override
    public void customize(Map<String, Object> properties) {
        properties.put(MultiTenancySettings.MULTI_TENANT_IDENTIFIER_RESOLVER, this);
    }
}
