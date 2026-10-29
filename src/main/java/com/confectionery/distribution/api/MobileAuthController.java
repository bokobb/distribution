package com.confectionery.distribution.api;

import com.confectionery.distribution.domain.AppEventKind;
import com.confectionery.distribution.security.LoginAttempts;
import com.confectionery.distribution.security.MobileAccounts;
import com.confectionery.distribution.security.MobileAccounts.Account;
import com.confectionery.distribution.security.MobileUser;
import com.confectionery.distribution.security.JwtService;
import com.confectionery.distribution.security.PasswordRules;
import com.confectionery.distribution.service.Phones;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Locale;
import java.util.Optional;

/**
 * Вход приложения, как в CRM: пароль — POST /login (JWT на 12 часов и ключ устройства), дальше приложение само
 * берёт новый JWT по ключу — POST /refresh, без пароля; «Выйти» — POST /logout закрывает ключ. Временный пароль
 * сначала меняется — POST /password. Ключ — в теле запроса, не в адресе: в журналы nginx он не попадает.
 */
@RestController
@RequiredArgsConstructor
public class MobileAuthController {

    private final MobileAccounts accounts;
    private final JwtService jwt;
    private final PasswordEncoder encoder;
    private final LoginAttempts attempts;
    private final JdbcTemplate jdbc;

    /** Хеш для сравнения, когда сотрудника нет: ответ «нет такого» не быстрее ответа «неверный пароль». */
    private String dummyHash;

    public record LoginRequest(String login, String password, String device, String appVersion) {
    }

    public record DeviceRequest(String deviceToken) {
    }

    public record PasswordRequest(String current, String password, String confirm, String deviceToken) {
    }

    public record UserDto(Long id, String name, String role, String company, String phone, boolean mustChangePassword) {
        static UserDto of(MobileUser u) {
            return new UserDto(u.id(), u.name(), u.role().name(), u.company(), u.phone(), u.mustChangePassword());
        }
    }

    /** token — JWT для заголовка Authorization, expiresIn — сколько секунд он живёт. */
    public record LoginResponse(String token, long expiresIn, String deviceToken, UserDto user) {
    }

    @PostMapping("/api/mobile/auth/login")
    public LoginResponse login(@RequestBody LoginRequest req) {
        String key = attemptKey(req.login());
        long wait = attempts.secondsLeft(key);
        if (wait > 0) throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "Много неверных попыток — подождите " + wait + " сек.");
        Optional<Account> found = accounts.byLogin(req.login());
        String password = req.password() == null ? "" : req.password();
        String hash = found.map(Account::passwordHash).orElse(null);
        boolean ok;
        if (hash != null) {
            ok = encoder.matches(password, hash);
        } else {
            encoder.matches(password, dummyHash()); // столько же времени, сколько проверка настоящего пароля
            ok = false;
        }
        if (!ok) {
            attempts.failed(key);
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Неверный телефон или пароль");
        }
        attempts.succeeded(key);
        Account a = found.get();
        if (!a.open()) throw new ApiException(HttpStatus.FORBIDDEN, "Вход закрыт — обратитесь к директору");
        if (!MobileUser.fieldRole(a.user().role()))
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "Приложение — для торговых агентов и экспедиторов. Директор, оператор и кладовщик работают в веб-админке.");
        accounts.journal(a.user(), AppEventKind.LOGIN, req.appVersion(), req.device());
        return response(a.user(), accounts.issue(a.user(), req.device()));
    }

    @PostMapping("/api/mobile/auth/refresh")
    public LoginResponse refresh(@RequestBody DeviceRequest req) {
        MobileUser u = accounts.use(req.deviceToken())
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Вход на этом телефоне закрыт — войдите с паролем"));
        return response(u, req.deviceToken().strip());
    }

    @PostMapping("/api/mobile/auth/logout")
    public ResponseEntity<Void> logout(@RequestBody DeviceRequest req) {
        accounts.revoke(req.deviceToken()).flatMap(accounts::byId)
                .ifPresent(a -> accounts.journal(a.user(), AppEventKind.LOGOUT, null, null));
        return ResponseEntity.noContent().build();
    }

    /** Смена пароля из приложения; вход на остальных телефонах сотрудника закрывается. */
    @PostMapping("/api/mobile/auth/password")
    public UserDto password(@AuthenticationPrincipal MobileUser me, @RequestBody PasswordRequest req) {
        Account a = accounts.byId(me.id()).orElseThrow();
        String problem = PasswordRules.problem(encoder, req.current(), req.password(), req.confirm(), a.passwordHash(), a.phone());
        if (problem != null) throw new ApiException(HttpStatus.BAD_REQUEST, problem);
        jdbc.update("update users set password_hash = ?, must_change_password = false where id = ?", encoder.encode(req.password()), me.id());
        accounts.revokeOthers(me.id(), req.deviceToken());
        return UserDto.of(accounts.byId(me.id()).orElseThrow().user());
    }

    @GetMapping("/api/mobile/me")
    public UserDto me(@AuthenticationPrincipal MobileUser me) {
        return UserDto.of(me);
    }

    private LoginResponse response(MobileUser u, String deviceToken) {
        return new LoginResponse(jwt.issue(u.id()), jwt.ttlSeconds(), deviceToken, UserDto.of(u));
    }

    private synchronized String dummyHash() {
        if (dummyHash == null) dummyHash = encoder.encode("нет такого сотрудника");
        return dummyHash;
    }

    private static String attemptKey(String login) {
        if (login == null) return "";
        String phone = Phones.normalize(login);
        return phone != null ? phone : login.strip().toLowerCase(Locale.ROOT);
    }
}
