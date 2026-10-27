package com.confectionery.distribution.tenant;

import java.util.function.Supplier;

/**
 * Чья компания сейчас открыта в этом потоке. Hibernate берёт её при открытии сессии
 * ({@link TenantResolver}) и добавляет условие company_id = … во все запросы к записям компании.
 *
 * <ul>
 *   <li>id компании — видна только она;</li>
 *   <li>{@link #ROOT} — владелец в режиме «Все компании» и служебные задачи (вход, демо-данные): без фильтра;</li>
 *   <li>{@link #NONE} или ничего — не видно ничего (запрос до входа не получит чужих данных).</li>
 * </ul>
 * Сессия Hibernate запоминает компанию при открытии: для веб-запроса её ставит TenantFilter до
 * открытия сессии, сменить посреди запроса нельзя.
 */
public final class TenantContext {

    public static final long ROOT = 0L;
    public static final long NONE = -1L;

    private static final ThreadLocal<Long> CURRENT = new ThreadLocal<>();

    private TenantContext() {
    }

    public static Long current() {
        return CURRENT.get();
    }

    public static void set(Long tenant) {
        if (tenant == null) CURRENT.remove();
        else CURRENT.set(tenant);
    }

    public static void clear() {
        CURRENT.remove();
    }

    /** Выполнить в компании (или ROOT); прежнее значение восстанавливается. */
    public static <T> T call(long tenant, Supplier<T> action) {
        Long prev = CURRENT.get();
        CURRENT.set(tenant);
        try {
            return action.get();
        } finally {
            set(prev);
        }
    }

    public static void run(long tenant, Runnable action) {
        call(tenant, () -> {
            action.run();
            return null;
        });
    }

    public static <T> T asRoot(Supplier<T> action) {
        return call(ROOT, action);
    }
}
