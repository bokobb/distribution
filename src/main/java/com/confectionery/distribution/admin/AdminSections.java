package com.confectionery.distribution.admin;

import com.confectionery.distribution.domain.Role;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.confectionery.distribution.domain.Role.*;

/**
 * Разделы меню: ключ (адрес /admin/{key}, он же имя значка), название, группа и роли, которым раздел
 * виден. Владелец (SUPER_ADMIN) видит всё; «Компании» — только он.
 */
public final class AdminSections {

    private AdminSections() {
    }

    public record Section(String key, String title, String group, Set<Role> roles) {
        public String href() {
            return "/admin/" + key;
        }

        public boolean visibleTo(Role role) {
            return role == SUPER_ADMIN || roles.contains(role);
        }
    }

    public static final List<Section> ALL = List.of(
            new Section("dashboard", "Дашборд", "", EnumSet.of(DIRECTOR, OPERATOR, STOREKEEPER)),
            new Section("orders", "Заказы", "Продажи", EnumSet.of(DIRECTOR, OPERATOR, STOREKEEPER)),
            new Section("outlets", "Магазины", "Продажи", EnumSet.of(DIRECTOR, OPERATOR)),
            new Section("debts", "Долги магазинов", "Продажи", EnumSet.of(DIRECTOR, OPERATOR)),
            new Section("routes", "Маршруты и регионы", "Продажи", EnumSet.of(DIRECTOR)),
            new Section("trips", "Рейсы", "Склад и доставка", EnumSet.of(DIRECTOR, OPERATOR, STOREKEEPER)),
            new Section("cash", "Приём кассы", "Склад и доставка", EnumSet.of(DIRECTOR, OPERATOR, STOREKEEPER)),
            new Section("stock", "Склад и приходы", "Склад и доставка", EnumSet.of(DIRECTOR, STOREKEEPER)),
            new Section("products", "Товары и прайс", "Каталог", EnumSet.of(DIRECTOR, OPERATOR)),
            new Section("staff", "Сотрудники и машины", "Команда", EnumSet.of(DIRECTOR)),
            new Section("reports", "Отчёты", "|", EnumSet.of(DIRECTOR, OPERATOR)),
            new Section("import", "Импорт из Doctor Sales", "|", EnumSet.of(DIRECTOR)),
            new Section("companies", "Компании", "|", EnumSet.noneOf(Role.class)),
            new Section("settings", "Настройки", "|", EnumSet.of(DIRECTOR)));

    public static Section byKey(String key) {
        return ALL.stream().filter(s -> s.key().equals(key)).findFirst().orElse(null);
    }

    /** Первый доступный роли раздел — куда вести после входа или при отказе в доступе. */
    public static Section home(Role role) {
        return ALL.stream().filter(s -> s.visibleTo(role)).findFirst().orElse(byKey("dashboard"));
    }

    /** Группа меню: подпись (пусто — без подписи, separator — после черты) и её пункты. */
    public record Group(String title, boolean separator, List<Section> items) {
    }

    public static List<Group> menu(Role role) {
        Map<String, List<Section>> groups = new LinkedHashMap<>();
        for (Section s : ALL) {
            if (s.visibleTo(role)) groups.computeIfAbsent(s.group(), g -> new ArrayList<>()).add(s);
        }
        return groups.entrySet().stream()
                .map(e -> new Group("|".equals(e.getKey()) ? "" : e.getKey(), "|".equals(e.getKey()), e.getValue()))
                .toList();
    }
}
