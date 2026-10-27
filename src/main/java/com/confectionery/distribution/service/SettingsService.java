package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.CompanySettings;
import com.confectionery.distribution.repository.CompanyRepository;
import com.confectionery.distribution.repository.CompanySettingsRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Настройки компании; если их ещё не сохраняли — значения по умолчанию. */
@Service
@RequiredArgsConstructor
public class SettingsService {

    private final CompanySettingsRepository settings;
    private final CompanyRepository companies;

    public CompanySettings of(Long companyId) {
        if (companyId == null) return new CompanySettings();
        return settings.findByCompanyId(companyId).orElseGet(CompanySettings::new);
    }

    /**
     * Сохранить настройки компании. «Клиент в CRM» меняет только владелец: по нему на этапе 7 к
     * компании пойдут отгрузки производства. Ключ API пока не хранится.
     */
    @Transactional
    public CompanySettings save(Long companyId, SettingsForm f, boolean owner) {
        if (companyId == null) throw new FormException("Выберите компанию в шапке, чтобы изменить её настройки");
        int radius = Forms.number(f.getVisitRadius(), "Радиус, метров", 10, 5000);
        if (f.getDeliveryDays() < 1 || f.getDeliveryDays() > 7) throw new FormException("Доставка — от 1 до 7 дней после заказа");
        long limit = Forms.money(f.getDefaultLimit(), "Лимит долга нового магазина");
        long tolerance = Forms.money(f.getCashTolerance(), "Допустимая разница при приёме");
        String crmClient = Forms.text(f.getCrmClient(), "Клиент в CRM", 200);

        CompanySettings st = settings.findByCompanyId(companyId).orElseGet(() -> {
            CompanySettings s = new CompanySettings();
            s.setCompany(companies.getReferenceById(companyId));
            return s;
        });
        st.setVisitRadius(radius).setShelfPhotoRequired(f.isShelfPhoto()).setRefuseReasonRequired(f.isRefuseReason())
                .setDeliveryDays(f.getDeliveryDays()).setDefaultCreditLimit(limit).setAllowCredit(f.isCredit())
                .setApprovalOverLimit(f.isApproval()).setAgentDiscount(f.isDiscount()).setCashTolerance(tolerance)
                .setAcceptKaspi(f.isKaspi()).setAutoReceipt(f.isAutoReceipt());
        settings.save(st);
        if (owner) {
            Company c = companies.findById(companyId).orElseThrow(NotFoundException::new);
            c.setCrmClient(crmClient);
        }
        return st;
    }
}
