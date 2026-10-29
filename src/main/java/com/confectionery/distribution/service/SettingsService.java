package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.CompanySettings;
import com.confectionery.distribution.repository.CompanyRepository;
import com.confectionery.distribution.repository.CompanySettingsRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalTime;

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

    /** Сохранить настройки компании. «Клиент в CRM» здесь не меняется — его выбирает владелец в «Компаниях». */
    @Transactional
    public CompanySettings save(Long companyId, SettingsForm f) {
        if (companyId == null) throw new FormException("Выберите компанию в шапке, чтобы изменить её настройки");
        int radius = Forms.number(f.getVisitRadius(), "Радиус, метров", 10, 5000);
        int gps = Forms.number(f.getGpsInterval(), "Интервал GPS, минут", 1, 60);
        LocalTime workStart = Forms.time(f.getWorkStart(), "Рабочее время с");
        LocalTime workEnd = Forms.time(f.getWorkEnd(), "Рабочее время до");
        if (!workStart.isBefore(workEnd)) throw new FormException("Рабочее время: «до» должно быть позже «с»");
        if (f.getDeliveryDays() < 1 || f.getDeliveryDays() > 7) throw new FormException("Доставка — от 1 до 7 дней после заказа");
        long limit = Forms.money(f.getDefaultLimit(), "Лимит долга нового магазина");
        long tolerance = Forms.money(f.getCashTolerance(), "Допустимая разница при приёме");
        int overdueDays = Forms.number(f.getOverdueDays(), "Запрет при просрочке: дней", 1, 365);
        long overdueAmount = Forms.money(f.getOverdueAmount(), "Запрет при просрочке: сумма");

        CompanySettings st = settings.findByCompanyId(companyId).orElseGet(() -> {
            CompanySettings s = new CompanySettings();
            s.setCompany(companies.getReferenceById(companyId));
            return s;
        });
        st.setVisitRadius(radius).setGpsInterval(gps).setWorkStart(workStart).setWorkEnd(workEnd).setShelfPhotoRequired(f.isShelfPhoto()).setRefuseReasonRequired(f.isRefuseReason())
                .setDeliveryDays(f.getDeliveryDays()).setDefaultCreditLimit(limit).setAllowCredit(f.isCredit())
                .setApprovalOverLimit(f.isApproval()).setAgentDiscount(f.isDiscount()).setCashTolerance(tolerance)
                .setAcceptKaspi(f.isKaspi()).setAutoReceipt(f.isAutoReceipt())
                .setFirstOrderCash(!"credit".equals(f.getFirstOrder())).setOverdueBlock(f.isOverdueBlock())
                .setOverdueDays(overdueDays).setOverdueAmount(overdueAmount).setUnblockDirector(f.isUnblockDirector())
                .setUnblockOperator(f.isUnblockOperator()).setUnderpayApproval(f.isUnderpay());
        settings.save(st);
        return st;
    }
}
