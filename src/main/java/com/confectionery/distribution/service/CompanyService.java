package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.*;
import com.confectionery.distribution.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Компании. Таблица общая (без фильтра компании), поэтому список целиком отдаётся только владельцу,
 * остальным — их компания.
 */
@Service
@RequiredArgsConstructor
public class CompanyService {

    private final CompanyRepository companies;
    private final CompanySettingsRepository settings;
    private final PriceTypeRepository priceTypes;
    private final WarehouseRepository warehouses;
    private final StaffService staff;
    private final Clock clock;

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

    /**
     * Новый склад-дилер (владелец, без фильтра компании): настройки по умолчанию, прайсы «Опт» и
     * «Розница», основной склад и склад негодного товара, директор с временным паролем.
     */
    @Transactional
    public IssuedPassword create(CompanyForm f) {
        String name = Forms.required(f.getName(), "Название", 200);
        if (all().stream().anyMatch(c -> c.getName().equalsIgnoreCase(name)))
            throw new FormException("Компания «" + name + "» уже есть");
        String director = Forms.required(f.getDirector(), "Директор (ФИО)", 200);
        Forms.required(f.getPhone(), "Телефон директора", 32);
        String crmClient = Forms.text(f.getCrmClient(), "Клиент в CRM", 200);
        freeCrmClient(f.getCrmClientId(), null);

        Company c = companies.save(new Company().setName(name).setDirector(director).setCrmClient(crmClient)
                .setCrmClientId(f.getCrmClientId()).setCreatedAt(LocalDateTime.now(clock)));
        IssuedPassword issued = staff.create(c, director, Role.DIRECTOR, f.getPhone(), null);
        c.setPhone(issued.phone());

        CompanySettings st = new CompanySettings();
        st.setCompany(c);
        settings.save(st);
        for (PriceKind kind : PriceKind.values()) {
            PriceType t = new PriceType().setCode(kind).setName(kind.getLabel());
            t.setCompany(c);
            priceTypes.save(t);
        }
        warehouse(c, WarehouseType.MAIN, "Основной склад");
        warehouse(c, WarehouseType.DEFECT, "Негодный товар");
        return issued;
    }

    /** Директор компании — клиент CRM (выбран из списка CRM); null — связь снята, приходов из CRM не будет. */
    @Transactional
    public Company linkCrm(Long companyId, Long clientId, String clientName) {
        Company c = get(companyId);
        freeCrmClient(clientId, companyId);
        c.setCrmClientId(clientId).setCrmClient(clientId == null ? null : Forms.required(clientName, "Клиент в CRM", 200));
        return c;
    }

    /** Один клиент CRM — одна компания: иначе отгрузку директора не разложить по складам. */
    private void freeCrmClient(Long clientId, Long except) {
        if (clientId == null) return;
        all().stream().filter(x -> clientId.equals(x.getCrmClientId()) && !x.getId().equals(except)).findFirst()
                .ifPresent(x -> {
                    throw new FormException("Этот клиент CRM уже директор компании «" + x.getName() + "»");
                });
    }

    private void warehouse(Company c, WarehouseType type, String name) {
        Warehouse w = new Warehouse().setType(type).setName(name);
        w.setCompany(c);
        warehouses.save(w);
    }
}
