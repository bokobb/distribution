package com.confectionery.distribution.service;

import java.time.LocalTime;

/** Разбор полей форм: пробелы по краям убираются, пустое поле — null, ошибка — {@link FormException}. */
public final class Forms {

    private Forms() {
    }

    /** Текст без пробелов по краям; пусто — null. */
    public static String text(String raw, String label, int max) {
        if (raw == null || raw.isBlank()) return null;
        String s = raw.strip();
        if (s.length() > max) throw new FormException("«" + label + "» — не длиннее " + max + " символов");
        return s;
    }

    public static String required(String raw, String label, int max) {
        String s = text(raw, label, max);
        if (s == null) throw new FormException("Заполните «" + label + "»");
        return s;
    }

    /** Сумма в тенге: целое ≥ 0, пробелы между разрядами и знак ₸ допустимы. Пусто — 0. */
    public static long money(String raw, String label) {
        String s = digits(raw);
        if (s == null) return 0;
        if (!s.matches("\\d{1,12}")) throw new FormException("«" + label + "» — целое число тенге, без копеек");
        return Long.parseLong(s);
    }

    /** Целое от min до max. Пусто — ошибка. */
    public static int number(String raw, String label, int min, int max) {
        String s = digits(raw);
        if (s == null || !s.matches("-?\\d{1,9}") || Integer.parseInt(s) < min || Integer.parseInt(s) > max)
            throw new FormException("«" + label + "» — число от " + min + " до " + max);
        return Integer.parseInt(s);
    }

    /** Время дня «08:00», «8:30», «8» (часы). Пусто или не время — ошибка. */
    public static LocalTime time(String raw, String label) {
        String s = raw == null ? "" : raw.strip().replace('.', ':');
        if (s.matches("\\d{1,2}")) s += ":00";
        if (s.matches("\\d{1,2}:\\d{2}")) {
            int h = Integer.parseInt(s.substring(0, s.indexOf(':'))), m = Integer.parseInt(s.substring(s.indexOf(':') + 1));
            if (h < 24 && m < 60) return LocalTime.of(h, m);
        }
        throw new FormException("«" + label + "» — время, например 08:00");
    }

    /** Координата: дробное число (точка или запятая) по модулю не больше limit. Пусто — null. */
    public static Double coord(String raw, String label, double limit) {
        if (raw == null || raw.isBlank()) return null;
        try {
            double d = Double.parseDouble(raw.strip().replace(',', '.'));
            if (Math.abs(d) <= limit) return d;
        } catch (NumberFormatException ignored) {
            // ниже — общая ошибка
        }
        throw new FormException("«" + label + "» — число от −" + (int) limit + " до " + (int) limit + ", например 43.2389");
    }

    private static String digits(String raw) {
        if (raw == null) return null;
        String s = raw.replaceAll("[\\s\\u00A0\\u202F₸]", "");
        return s.isEmpty() ? null : s;
    }
}
