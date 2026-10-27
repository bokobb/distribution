package com.confectionery.distribution.admin;

import java.util.ArrayList;
import java.util.List;

/** Сумма прописью для накладных (до 999 миллиардов): 112 440 → «Сто двенадцать тысяч четыреста сорок тенге». */
final class MoneyWords {

    private static final String[] ONES = {"", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"};
    private static final String[] ONES_F = {"", "одна", "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"};
    private static final String[] TEENS = {"десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать",
            "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать"};
    private static final String[] TENS = {"", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят",
            "семьдесят", "восемьдесят", "девяносто"};
    private static final String[] HUNDREDS = {"", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот",
            "семьсот", "восемьсот", "девятьсот"};
    /** Разряды от старшего: миллиарды, миллионы, тысячи (женский род), единицы. */
    private static final String[][] SCALES = {
            {"миллиард", "миллиарда", "миллиардов"},
            {"миллион", "миллиона", "миллионов"},
            {"тысяча", "тысячи", "тысяч"},
            null};

    private MoneyWords() {
    }

    static String tenge(long amount) {
        if (amount == 0) return "Ноль тенге";
        List<String> words = new ArrayList<>();
        if (amount < 0) words.add("минус");
        long n = Math.abs(amount);
        long scale = 1_000_000_000L;
        for (int i = 0; i < SCALES.length; i++, scale /= 1000) {
            int part = (int) (n / scale % 1000);
            if (part == 0) continue;
            triad(part, i == 2, words);
            if (SCALES[i] != null) words.add(form(part, SCALES[i]));
        }
        String s = String.join(" ", words) + " тенге";
        return Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }

    private static void triad(int n, boolean feminine, List<String> out) {
        if (n / 100 > 0) out.add(HUNDREDS[n / 100]);
        int rest = n % 100;
        if (rest >= 10 && rest < 20) {
            out.add(TEENS[rest - 10]);
            return;
        }
        if (rest / 10 > 0) out.add(TENS[rest / 10]);
        if (rest % 10 > 0) out.add((feminine ? ONES_F : ONES)[rest % 10]);
    }

    private static String form(int n, String[] forms) {
        int a = n % 100, b = a % 10;
        return a > 10 && a < 20 ? forms[2] : b == 1 ? forms[0] : b >= 2 && b <= 4 ? forms[1] : forms[2];
    }
}
