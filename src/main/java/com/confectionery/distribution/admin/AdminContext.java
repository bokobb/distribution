package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Employee;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.repository.CompanyRepository;
import com.confectionery.distribution.repository.EmployeeRepository;
import com.confectionery.distribution.tenant.TenantContext;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;

/**
 * Кто смотрит и в какой компании (см. {@link Viewer}). Собирается в начале запроса ({@link TenantFilter}),
 * до того как откроется сессия базы, — по нему же выбирается компания для фильтра Hibernate.
 *
 * <p>ЗАГЛУШКА входа: роль выбирается переключателем «Смотреть как» и хранится в сессии; её заменит
 * настоящий вход (Spring Security), а компания у не-владельцев будет из профиля.
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

    /** Собрать Viewer из сессии. Чтение — без фильтра компании: компания ещё не выбрана. */
    public Viewer resolve(HttpSession session) {
        return TenantContext.asRoot(() -> {
            Role role = session.getAttribute(ROLE) instanceof Role r ? r : Role.SUPER_ADMIN;
            Long cid = session.getAttribute(COMPANY) instanceof Long l ? l : null;
            Company c = cid == null ? null : companies.findById(cid).orElse(null);
            if (c == null && role != Role.SUPER_ADMIN) {
                c = companies.findAllByOrderByIdAsc().stream().findFirst().orElse(null); // не-владелец всегда в своей компании
            }
            Long id = c == null ? null : c.getId();
            return new Viewer(role, id, c, me(id, role), true);
        });
    }

    /** «Кто вошёл» в режиме просмотра под ролью: первый сотрудник компании с этой ролью. */
    private Employee me(Long cid, Role role) {
        if (role != Role.SUPER_ADMIN && cid != null) {
            Employee e = employees.findFirstByCompanyIdAndRoleOrderByIdAsc(cid, role).orElse(null);
            if (e != null) return e;
        }
        return new Employee().setName("Владелец").setRole(Role.SUPER_ADMIN);
    }

    public void setRole(HttpSession session, Role role) {
        session.setAttribute(ROLE, role);
    }

    /** companyId = null — «Все компании»; доступно только владельцу. */
    public void setCompany(HttpSession session, Long companyId) {
        if (companyId != null && TenantContext.asRoot(() -> companies.findById(companyId)).isEmpty()) return;
        if (companyId == null) session.removeAttribute(COMPANY);
        else session.setAttribute(COMPANY, companyId);
    }

    public void toast(HttpSession session, String text) {
        session.setAttribute(TOAST, text);
    }
}
