package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.CompanySettings;
import com.confectionery.distribution.repository.CompanySettingsRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/** Настройки компании; если их ещё не сохраняли — значения по умолчанию. */
@Service
@RequiredArgsConstructor
public class SettingsService {

    private final CompanySettingsRepository settings;

    public CompanySettings of(Long companyId) {
        if (companyId == null) return new CompanySettings();
        return settings.findByCompanyId(companyId).orElseGet(CompanySettings::new);
    }
}
