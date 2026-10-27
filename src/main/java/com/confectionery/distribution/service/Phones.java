package com.confectionery.distribution.service;

/** Телефоны Казахстана: вход по номеру хранится как +7 и 10 цифр. */
public final class Phones {

    private Phones() {
    }

    /** «8 701 123 45 67», «+7 (701) 123-45-67», «7011234567» → «+77011234567»; не номер — null. */
    public static String normalize(String raw) {
        if (raw == null) return null;
        String d = raw.replaceAll("\\D", "");
        if (d.length() == 11 && (d.startsWith("8") || d.startsWith("7"))) d = d.substring(1);
        return d.length() == 10 ? "+7" + d : null;
    }

    /** «+77011234567» → «+7 701 123 45 67»; другое — как есть. */
    public static String format(String phone) {
        if (phone == null || !phone.matches("\\+7\\d{10}")) return phone;
        String d = phone.substring(2);
        return "+7 " + d.substring(0, 3) + " " + d.substring(3, 6) + " " + d.substring(6, 8) + " " + d.substring(8);
    }
}
