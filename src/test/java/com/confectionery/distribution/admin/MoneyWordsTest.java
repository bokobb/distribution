package com.confectionery.distribution.admin;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** Сумма прописью в накладной: род у тысяч, «-надцать», склонение разрядов. */
class MoneyWordsTest {

    @Test
    void прописью() {
        assertThat(MoneyWords.tenge(0)).isEqualTo("Ноль тенге");
        assertThat(MoneyWords.tenge(1)).isEqualTo("Один тенге");
        assertThat(MoneyWords.tenge(15)).isEqualTo("Пятнадцать тенге");
        assertThat(MoneyWords.tenge(112_440)).isEqualTo("Сто двенадцать тысяч четыреста сорок тенге");
        assertThat(MoneyWords.tenge(21_000)).isEqualTo("Двадцать одна тысяча тенге");
        assertThat(MoneyWords.tenge(2_002_000)).isEqualTo("Два миллиона две тысячи тенге");
        assertThat(MoneyWords.tenge(11_514_011)).isEqualTo("Одиннадцать миллионов пятьсот четырнадцать тысяч одиннадцать тенге");
        assertThat(MoneyWords.tenge(5_000_000_000L)).isEqualTo("Пять миллиардов тенге");
        assertThat(MoneyWords.tenge(-300)).isEqualTo("Минус триста тенге");
    }
}
