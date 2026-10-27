package com.confectionery.distribution.security;

import com.confectionery.distribution.admin.AdminContext;
import jakarta.servlet.http.HttpSession;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Страница входа (сам вход проверяет Spring Security, см. SecurityConfig) и смена пароля. Пароль
 * меняется прямым запросом к users: компании на этой странице ещё нет, а фильтр компании спрятал бы
 * и самого сотрудника.
 */
@Controller
@RequiredArgsConstructor
public class LoginController {

    private final JdbcTemplate jdbc;
    private final AdminContext ctx;
    private final PasswordEncoder encoder;

    @GetMapping("/login")
    public String login(@RequestParam(required = false) String error, @RequestParam(required = false) String logout,
                        @RequestParam(required = false) String closed, Authentication auth, Model model) {
        if (auth != null && auth.getPrincipal() instanceof AdminUser) return "redirect:/admin";
        if (error != null) model.addAttribute("error", "Не удалось войти: проверьте телефон (или логин) и пароль. "
                + "Торговые агенты и экспедиторы работают в приложении на телефоне.");
        if (closed != null) model.addAttribute("error", "Вход закрыт — обратитесь к директору.");
        if (logout != null) model.addAttribute("info", "Вы вышли из админки.");
        return "login";
    }

    @GetMapping("/password")
    public String password(@AuthenticationPrincipal AdminUser user, Model model) {
        model.addAttribute("forced", mustChange(user));
        return "password";
    }

    @PostMapping("/password")
    public String changePassword(@AuthenticationPrincipal AdminUser user, @RequestParam String current,
                                 @RequestParam String password, @RequestParam String confirm, Model model, HttpSession session) {
        List<String[]> rows = jdbc.query("select password_hash, phone from users where id = ?",
                (rs, n) -> new String[]{rs.getString(1), rs.getString(2)}, user.getId());
        String error = rows.isEmpty() ? "Сотрудник не найден"
                : check(current, password, confirm, rows.get(0)[0], rows.get(0)[1]);
        if (error != null) {
            model.addAttribute("error", error);
            model.addAttribute("forced", mustChange(user));
            return "password";
        }
        jdbc.update("update users set password_hash = ?, must_change_password = false where id = ?",
                encoder.encode(password), user.getId());
        ctx.toast(session, "Пароль изменён");
        return "redirect:/admin";
    }

    private String check(String current, String password, String confirm, String hash, String phone) {
        if (hash == null || !encoder.matches(current, hash)) return "Текущий пароль неверный";
        if (password.length() < 8) return "Новый пароль — не короче 8 знаков";
        if (password.getBytes(StandardCharsets.UTF_8).length > 72) return "Новый пароль слишком длинный";
        if (!password.equals(confirm)) return "Новый пароль и повтор не совпадают";
        if (password.equals(current)) return "Новый пароль совпадает с прежним";
        String digits = password.replaceAll("\\D", "");
        if (!digits.isEmpty() && phone.endsWith(digits) && digits.length() >= 7) return "Пароль не должен быть номером телефона";
        return null;
    }

    private boolean mustChange(AdminUser user) {
        return Boolean.TRUE.equals(jdbc.queryForObject("select must_change_password from users where id = ?", Boolean.class, user.getId()));
    }
}
