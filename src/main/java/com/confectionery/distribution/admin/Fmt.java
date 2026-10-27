package com.confectionery.distribution.admin;

import com.confectionery.distribution.service.Phones;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.TextStyle;
import java.util.Locale;

/** Форматирование для шаблонов: ${@fmt.money(x)}, ${@fmt.day(d)} и т.д. */
@Component("fmt")
@RequiredArgsConstructor
public class Fmt {

    private static final Locale RU = Locale.forLanguageTag("ru");
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("HH:mm");
    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("dd.MM.yyyy");
    /** Узкий неразрывный пробел между разрядами: «1 284 000». */
    private static final char NB = '\u202F';

    private final Clock clock;

    /** Числа из шаблонов приходят разными типами (int, long, Long) — принимаем любое. */
    public String num(Number n) {
        if (n == null) return "—";
        long v = n.longValue();
        String s = String.format(Locale.ROOT, "%,d", Math.abs(v)).replace(',', NB);
        return v < 0 ? "−" + s : s;
    }

    public String money(Number v) {
        return v == null ? "—" : num(v) + "\u00A0₸";
    }

    /** Сумма со знаком: «+500 ₸», «−500 ₸», «0 ₸». */
    public String signed(Number v) {
        if (v == null) return "—";
        return (v.longValue() > 0 ? "+" : "") + money(v);
    }

    public String time(LocalDateTime t) {
        return t == null ? "—" : t.format(TIME);
    }

    public String date(LocalDate d) {
        return d == null ? "—" : d.format(DATE);
    }

    /** «28 окт», «вчера», «сегодня», «завтра». */
    public String day(LocalDate d) {
        if (d == null) return "—";
        LocalDate today = LocalDate.now(clock);
        if (d.equals(today)) return "сегодня";
        if (d.equals(today.minusDays(1))) return "вчера";
        if (d.equals(today.plusDays(1))) return "завтра";
        return d.getDayOfMonth() + " " + d.getMonth().getDisplayName(TextStyle.SHORT, RU).replace(".", "");
    }

    /** «среда, 28 октября». */
    public String longDay(LocalDate d) {
        if (d == null) return "—";
        return d.getDayOfWeek().getDisplayName(TextStyle.FULL, RU) + ", " + d.getDayOfMonth() + " "
                + d.getMonth().getDisplayName(TextStyle.FULL, RU);
    }

    /** «28 окт, 11:40» или «сегодня, 11:40». */
    public String when(LocalDateTime t) {
        return t == null ? "—" : day(t.toLocalDate()) + ", " + time(t);
    }

    /** «5 мин назад», «3 ч назад», «2 дн назад». */
    public String ago(LocalDateTime t) {
        if (t == null) return "никогда";
        long min = Duration.between(t, LocalDateTime.now(clock)).toMinutes();
        if (min < 1) return "только что";
        if (min < 60) return min + " мин назад";
        if (min < 48 * 60) return (min / 60) + " ч назад";
        return (min / 60 / 24) + " дн назад";
    }

    /** Подпись через точку без пустых частей: dot(адрес, филиал, компания) → «ул. Абая 5 · Центр». */
    public String dot(Object... parts) {
        StringBuilder b = new StringBuilder();
        for (Object p : parts) {
            if (p == null || p.toString().isBlank()) continue;
            if (!b.isEmpty()) b.append(" · ");
            b.append(p);
        }
        return b.toString();
    }

    /** Склонение: plural(5, "магазин", "магазина", "магазинов"). */
    public String plural(Number count, String one, String few, String many) {
        long n = count == null ? 0 : count.longValue();
        long a = Math.abs(n) % 100, b = a % 10;
        String w = a > 10 && a < 20 ? many : b == 1 ? one : b >= 2 && b <= 4 ? few : many;
        return num(n) + " " + w;
    }

    /** «+77011234567» → «+7 701 123 45 67»; пусто — «—». */
    public String phone(String p) {
        return p == null || p.isBlank() ? "—" : Phones.format(p);
    }
}
