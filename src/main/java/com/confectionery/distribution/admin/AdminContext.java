package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.repository.CompanyRepository;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.security.AdminUser;
import com.confectionery.distribution.tenant.TenantContext;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;

/**
 * Кто смотрит и в какой компании (см. {@link Viewer}). Собирается в начале запроса ({@link TenantFilter}),
 * до того как откроется сессия базы, — по нему же выбирается компания для фильтра Hibernate.
 *
 * <p>Сотрудник — из входа и каждый раз из базы: компания и роль — его, менять их нельзя. Владелец
 * выбирает компанию в шапке и может посмотреть админку глазами другой роли («Смотреть как») — это
 * хранится в сессии; действия при этом записываются на него самого.
 */
@Component
@RequiredArgsConstructor
public class AdminContext {

    static final String ROLE = "ADM_ROLE";
    static final String COMPANY = "ADM_COMPANY";
    static final String TOAST = "ADM_TOAST";
    static final String VIEWER = AdminContext.class.getName() + ".viewer";

    private final CompanyRepository companies;
    private final EmployeeRepository employees;

    /** Viewer этого запроса. */
    public Viewer viewer(HttpSession session) {
        RequestAttributes ra = RequestContextHolder.getRequestAttributes();
        if (ra != null && ra.getAttribute(VIEWER, RequestAttributes.SCOPE_REQUEST) instanceof Viewer v) return v;
        return resolve(session);
    }

    /**
     * Собрать Viewer по вошедшему сотруднику. null — входа нет, сотрудник удалён, отключён или его роль
     * не для веба: такую сессию надо закрыть. Чтение — без фильтра компании: компания ещё не выбрана.
     */
    public Viewer resolve(HttpSession session) {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof AdminUser user)) return null;
        return TenantContext.asRoot(() -> {
            Employee me = employees.findById(user.getId()).orElse(null);
            if (me == null || !me.isActive() || !me.getRole().webAdmin()) return null;
            if (me.getRole() != Role.SUPER_ADMIN) {
                Company c = companies.findById(me.getCompanyId()).orElse(null);
                return c == null ? null : new Viewer(me.getRole(), c.getId(), c, me, false);
            }
            Role role = session.getAttribute(ROLE) instanceof Role r ? r : Role.SUPER_ADMIN;
            Long cid = session.getAttribute(COMPANY) instanceof Long l ? l : null;
            Company c = cid == null ? null : companies.findById(cid).orElse(null);
            if (c == null && role != Role.SUPER_ADMIN) {
                c = companies.findAllByOrderByIdAsc().stream().findFirst().orElse(null); // другая роль — всегда в одной компании
            }
            return new Viewer(role, c == null ? null : c.getId(), c, me, true);
        });
    }

    /** «Смотреть как» — только владельцу (проверяет вызывающий). */
    public void setRole(HttpSession session, Role role) {
        session.setAttribute(ROLE, role);
    }

    /** companyId = null — «Все компании»; только владельцу (проверяет вызывающий). */
    public void setCompany(HttpSession session, Long companyId) {
        if (companyId != null && TenantContext.asRoot(() -> companies.findById(companyId)).isEmpty()) return;
        if (companyId == null) session.removeAttribute(COMPANY);
        else session.setAttribute(COMPANY, companyId);
    }

    public void toast(HttpSession session, String text) {
        session.setAttribute(TOAST, text);
    }
}
