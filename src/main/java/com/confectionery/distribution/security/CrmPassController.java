package com.confectionery.distribution.security;

import com.confectionery.distribution.admin.AdminContext;
import com.confectionery.distribution.domain.Role;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.security.web.context.SecurityContextRepository;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.util.HexFormat;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Вход владельца из CRM: CRM подписывает пропуск общим ключом (CRM_KEY), пропуск действует минуту и только один
 * раз. Входит первый активный владелец; в журнале входов — кто открыл из CRM.
 */
@Controller
public class CrmPassController {

    private static final long TTL_SECONDS = 60;

    private final String key;
    private final JdbcTemplate jdbc;
    private final LoginJournal journal;
    private final Clock clock;
    private final SecurityContextRepository contexts = new HttpSessionSecurityContextRepository();
    /** Использованные пропуски (одноразовые): номер → когда, старше двух минут забываются. */
    private final Map<String, Long> used = new LinkedHashMap<>();

    public CrmPassController(@Value("${distribution.crm.key:}") String key, JdbcTemplate jdbc, LoginJournal journal, Clock clock) {
        this.key = key == null ? "" : key.trim();
        this.jdbc = jdbc;
        this.journal = journal;
        this.clock = clock;
    }

    @GetMapping("/crm-pass")
    public String pass(@RequestParam String ts, @RequestParam String n, @RequestParam String who, @RequestParam String sig,
                       HttpServletRequest req, HttpServletResponse res) {
        long now = clock.instant().getEpochSecond();
        long at;
        try {
            at = Long.parseLong(ts);
        } catch (NumberFormatException e) {
            return "redirect:/login?pass";
        }
        if (key.isEmpty() || Math.abs(now - at) > TTL_SECONDS || !MessageDigest.isEqual(
                sign("pass|" + ts + "|" + n + "|" + who).getBytes(StandardCharsets.UTF_8), sig.getBytes(StandardCharsets.UTF_8)))
            return "redirect:/login?pass";
        if (!firstUse(n, now)) return "redirect:/login?pass";
        // владелец — прямым запросом: сессия JPA этого запроса уже открыта «без компании» и владельца не увидит
        List<AdminUser> owners = jdbc.query("""
                select id, phone, password_hash from users where role = 'SUPER_ADMIN' and active order by id limit 1""",
                (rs, i) -> new AdminUser(rs.getLong(1), rs.getString(2), rs.getString(3) == null ? "" : rs.getString(3), true,
                        List.of(new SimpleGrantedAuthority("ROLE_" + Role.SUPER_ADMIN.name()))));
        if (owners.isEmpty()) return "redirect:/login?pass";
        AdminUser u = owners.get(0);
        if (req.getSession(false) != null) req.changeSessionId();
        SecurityContext ctx = SecurityContextHolder.createEmptyContext();
        ctx.setAuthentication(UsernamePasswordAuthenticationToken.authenticated(u, null, u.getAuthorities()));
        SecurityContextHolder.setContext(ctx);
        contexts.saveContext(ctx, req, res);
        req.getSession().setAttribute(AdminContext.CRM_PASS, true);
        journal.log(u.getId(), "CRM", who.length() > 120 ? who.substring(0, 120) : who, LoginJournal.ip(req));
        return "redirect:/admin";
    }

    private synchronized boolean firstUse(String nonce, long now) {
        for (Iterator<Map.Entry<String, Long>> it = used.entrySet().iterator(); it.hasNext(); ) {
            if (now - it.next().getValue() > 2 * TTL_SECONDS) it.remove();
            else break;
        }
        return used.putIfAbsent(nonce, now) == null;
    }

    private String sign(String text) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(text.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException("HMAC недоступен", e);
        }
    }
}
