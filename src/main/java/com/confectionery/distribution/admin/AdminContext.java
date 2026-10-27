package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Company;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.stub.StubStore;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/** Роль и выбранная компания из сессии (см. {@link Viewer}). */
@Component
@RequiredArgsConstructor
public class AdminContext {

    static final String ROLE = "ADM_ROLE";
    static final String COMPANY = "ADM_COMPANY";
    static final String TOAST = "ADM_TOAST";

    private final StubStore store;

    public Viewer viewer(HttpSession session) {
        Role role = session.getAttribute(ROLE) instanceof Role r ? r : Role.SUPER_ADMIN;
        Long cid = session.getAttribute(COMPANY) instanceof Long l ? l : null;
        if (role != Role.SUPER_ADMIN && cid == null) {
            cid = store.companies().get(0).getId(); // не-владелец всегда в своей компании
        }
        Company c = store.company(cid);
        return new Viewer(role, cid, c, store.firstWithRole(cid, role));
    }

    public void setRole(HttpSession session, Role role) {
        session.setAttribute(ROLE, role);
    }

    /** companyId = null — «Все компании»; доступно только владельцу. */
    public void setCompany(HttpSession session, Long companyId) {
        if (companyId != null && store.company(companyId) == null) return;
        if (companyId == null) session.removeAttribute(COMPANY);
        else session.setAttribute(COMPANY, companyId);
    }

    public void toast(HttpSession session, String text) {
        session.setAttribute(TOAST, text);
    }
}
