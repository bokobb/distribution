package com.confectionery.distribution.security;

import com.confectionery.distribution.admin.AdminContext;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.event.InteractiveAuthenticationSuccessEvent;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

/** Журнал входов в админку: паролем на странице входа или пропуском владельца из CRM. */
@Component
@RequiredArgsConstructor
public class LoginJournal {

    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** Вход: когда, кто, как — паролем или пропуском из CRM, в какую компанию (null — все), с какого адреса. */
    public record Entry(LocalDateTime at, String who, String via, String ip, String company) {
        public boolean crm() {
            return "CRM".equals(via);
        }
    }

    public void log(Long employeeId, String via, String who, String ip) {
        jdbc.update("insert into login_log (at, employee_id, via, who, ip) values (?, ?, ?, ?, ?)",
                Timestamp.valueOf(LocalDateTime.now(clock)), employeeId, via, who.length() > 200 ? who.substring(0, 200) : who, ip);
    }

    public List<Entry> recent(int limit) {
        return jdbc.query("""
                select l.at, l.who, l.via, l.ip, c.name from login_log l
                left join users u on u.id = l.employee_id left join companies c on c.id = u.company_id
                order by l.at desc limit ?""",
                (rs, i) -> new Entry(rs.getTimestamp(1).toLocalDateTime(), rs.getString(2), rs.getString(3), rs.getString(4),
                        rs.getString(5)), limit);
    }

    /** Вход паролем на странице /login. */
    @EventListener
    public void onLogin(InteractiveAuthenticationSuccessEvent e) {
        if (!(e.getAuthentication().getPrincipal() instanceof AdminUser u)) return;
        String who = jdbc.query("select name from users where id = ?", rs -> rs.next() ? rs.getString(1) : u.getUsername(), u.getId());
        log(u.getId(), "PASSWORD", who, ip(null));
        // вход паролем после пропуска из CRM — уже не «из CRM»
        if (RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes a && a.getRequest().getSession(false) != null)
            a.getRequest().getSession(false).removeAttribute(AdminContext.CRM_PASS);
    }

    static String ip(HttpServletRequest req) {
        if (req == null && RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes a) req = a.getRequest();
        if (req == null) return null;
        String fwd = req.getHeader("X-Forwarded-For");
        String ip = fwd != null && !fwd.isBlank() ? fwd.split(",")[0].strip() : req.getRemoteAddr();
        return ip != null && ip.length() > 64 ? ip.substring(0, 64) : ip;
    }
}
