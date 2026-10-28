package com.confectionery.distribution.security;

import com.confectionery.distribution.domain.AppEventKind;
import com.confectionery.distribution.domain.Role;
import com.confectionery.distribution.service.Phones;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;

/**
 * Сотрудники приложения и ключи устройств (device_sessions), как в CRM: пароль — один раз на телефоне, дальше
 * приложение само берёт новый JWT по ключу. Ключ живёт, пока телефоном пользуются (не дольше {@link #IDLE} без
 * единого продления). Всё — прямыми запросами мимо фильтра компании: до входа компания ещё не известна.
 */
@Service
@RequiredArgsConstructor
public class MobileAccounts {

    public static final Duration IDLE = Duration.ofDays(180);
    private static final int MAX_PER_USER = 10;
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcTemplate jdbc;
    private final Clock clock;

    /** Сотрудник для входа по паролю: open — сотрудник и его компания не отключены. */
    public record Account(MobileUser user, String passwordHash, String phone, boolean open) {
    }

    private static final String SELECT = "select u.id, u.company_id, u.role, u.name, c.name, u.must_change_password, "
            + "u.password_hash, u.phone, u.active and coalesce(c.active, true) from users u left join companies c on c.id = u.company_id ";

    private static final RowMapper<Account> ACCOUNT = (rs, n) -> new Account(
            new MobileUser(rs.getLong(1), rs.getObject(2, Long.class), Role.valueOf(rs.getString(3)), rs.getString(4),
                    rs.getString(5), rs.getBoolean(6)),
            rs.getString(7), rs.getString(8), rs.getBoolean(9));

    /** По телефону в любом виде или по логину. */
    public Optional<Account> byLogin(String input) {
        if (input == null || input.isBlank()) return Optional.empty();
        String phone = Phones.normalize(input);
        List<Account> rows = phone != null ? jdbc.query(SELECT + "where u.phone = ?", ACCOUNT, phone)
                : jdbc.query(SELECT + "where u.login = ?", ACCOUNT, input.strip().toLowerCase(Locale.ROOT));
        return rows.stream().findFirst();
    }

    public Optional<Account> byId(Long id) {
        return jdbc.query(SELECT + "where u.id = ?", ACCOUNT, id).stream().findFirst();
    }

    /** Кто работает в приложении — на каждом запросе: нет, отключён или роль не для приложения — пусто. */
    public Optional<MobileUser> active(Long id) {
        return byId(id).filter(a -> a.open() && MobileUser.fieldRole(a.user().role())).map(Account::user);
    }

    /** Новый ключ устройства — отдаётся телефону один раз, в базе остаётся только хеш. */
    @Transactional
    public String issue(MobileUser user, String device) {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        String raw = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        LocalDateTime now = LocalDateTime.now(clock);
        jdbc.update("insert into device_sessions (company_id, user_id, token_hash, device, created_at, last_used_at) values (?, ?, ?, ?, ?, ?)",
                user.companyId(), user.id(), hash(raw), cut(device, 100), now, now);
        jdbc.update("delete from device_sessions where last_used_at < ?", now.minus(IDLE));
        jdbc.update("delete from device_sessions where user_id = ? and id not in "
                + "(select id from device_sessions where user_id = ? order by last_used_at desc, id desc limit ?)", user.id(), user.id(), MAX_PER_USER);
        return raw;
    }

    /** Продление по ключу: сотрудник, если ключ жив и вход открыт; иначе пусто, ключ стирается. */
    @Transactional
    public Optional<MobileUser> use(String raw) {
        if (raw == null || raw.isBlank()) return Optional.empty();
        String hash = hash(raw.strip());
        List<Object[]> rows = jdbc.query("select user_id, last_used_at from device_sessions where token_hash = ?",
                (rs, n) -> new Object[]{rs.getLong(1), rs.getObject(2, LocalDateTime.class)}, hash);
        if (rows.isEmpty()) return Optional.empty();
        LocalDateTime now = LocalDateTime.now(clock);
        Optional<MobileUser> user = ((LocalDateTime) rows.get(0)[1]).isBefore(now.minus(IDLE)) ? Optional.empty()
                : active((Long) rows.get(0)[0]);
        if (user.isEmpty()) jdbc.update("delete from device_sessions where token_hash = ?", hash);
        else jdbc.update("update device_sessions set last_used_at = ? where token_hash = ?", now, hash);
        return user;
    }

    /** Закрыть ключ; чей он был — пусто, если ключа нет. */
    @Transactional
    public Optional<Long> revoke(String raw) {
        if (raw == null || raw.isBlank()) return Optional.empty();
        String hash = hash(raw.strip());
        List<Long> users = jdbc.queryForList("select user_id from device_sessions where token_hash = ?", Long.class, hash);
        jdbc.update("delete from device_sessions where token_hash = ?", hash);
        return users.stream().findFirst();
    }

    /** Закрыть вход на всех телефонах сотрудника; сколько было. */
    @Transactional
    public int revokeAll(Long userId) {
        return jdbc.update("delete from device_sessions where user_id = ?", userId);
    }

    /** Закрыть вход на остальных телефонах сотрудника — кроме этого ключа. */
    @Transactional
    public void revokeOthers(Long userId, String keepRaw) {
        jdbc.update("delete from device_sessions where user_id = ? and token_hash <> ?", userId,
                keepRaw == null ? "" : hash(keepRaw.strip()));
    }

    /** Запись журнала приложения от сервера: вход и выход. */
    public void journal(MobileUser user, AppEventKind kind, String appVersion, String device) {
        LocalDateTime now = LocalDateTime.now(clock);
        jdbc.update("insert into app_events (company_id, uuid, user_id, event_at, kind, app_version, device, received_at) values (?, ?, ?, ?, ?, ?, ?, ?)",
                user.companyId(), UUID.randomUUID(), user.id(), now, kind.name(), cut(appVersion, 32), cut(device, 100), now);
    }

    static String hash(String raw) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String cut(String s, int max) {
        if (s == null || s.isBlank()) return null;
        s = s.strip();
        return s.length() > max ? s.substring(0, max) : s;
    }
}
