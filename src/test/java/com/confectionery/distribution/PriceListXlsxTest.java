package com.confectionery.distribution;

import com.confectionery.distribution.domain.Product;
import com.confectionery.distribution.service.PriceListXlsx;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** «Скачать прайс» (09.11.2026): что и в каком порядке лежит в Excel — без базы и Spring. */
class PriceListXlsxTest {

    private static Product product(String name, String category, int perBox, long price, boolean active) {
        Product p = new Product().setName(name).setCategory(category).setPerBox(perBox).setActive(active).setCrmPrice(777L);
        p.setWholesale(price);
        p.setRetail(price);
        return p;
    }

    /** Строки листа текстом, как их видит человек (пустые ячейки — ""). */
    static List<List<String>> sheet(byte[] xlsx) throws Exception {
        try (XSSFWorkbook wb = new XSSFWorkbook(new ByteArrayInputStream(xlsx))) {
            Sheet ws = wb.getSheetAt(0);
            DataFormatter f = new DataFormatter();
            List<List<String>> out = new ArrayList<>();
            for (int i = 0; i <= ws.getLastRowNum(); i++) {
                Row r = ws.getRow(i);
                List<String> cells = new ArrayList<>();
                if (r != null) for (int c = 0; c < r.getLastCellNum(); c++)
                    cells.add(r.getCell(c) == null ? "" : f.formatCellValue(r.getCell(c)).replace(' ', ' '));
                out.add(cells);
            }
            return out;
        }
    }

    @Test
    void группыПоПорядку_нумерацияСквозная_безЦеныИВыключенныхНет() throws Exception {
        List<Product> list = List.of(
                product("Шоколадное", "Печенье", 10, 1250, true),
                product("Овсяное", "Печенье", 12, 900, true),
                product("Вафли без цены", "Вафли", 6, 0, true),
                product("Медовик", "Вафли", 1, 3500, true),
                product("Старый торт", "Торты", 1, 5000, false));

        List<List<String>> rows = sheet(new PriceListXlsx().write("Олимжон", "+77010000000", LocalDate.of(2026, 11, 9), list));

        assertThat(rows.get(0).get(0)).isEqualTo("Прайс-лист — Олимжон");
        assertThat(rows.get(1).get(0)).isEqualTo("Цены на 09.11.2026 · тел. +77010000000");
        assertThat(rows.get(3)).containsExactly("№", "Товар", "В коробке, шт", "Цена за шт, ₸", "Цена за коробку, ₸");
        assertThat(rows.subList(4, 9)).containsExactly(
                List.of("Вафли", "", "", "", ""),
                List.of("1", "Медовик", "1", "3 500", "3 500"),
                List.of("Печенье", "", "", "", ""),
                List.of("2", "Овсяное", "12", "900", "10 800"),
                List.of("3", "Шоколадное", "10", "1 250", "12 500"));
        String all = rows.toString();
        assertThat(all).doesNotContain("777").doesNotContain("Вафли без цены").doesNotContain("Старый торт");
        assertThat(PriceListXlsx.rows(list)).hasSize(3);
    }

    @Test
    void пустойПрайс_безТелефона() throws Exception {
        List<List<String>> rows = sheet(new PriceListXlsx().write("Олимжон", null, LocalDate.of(2026, 11, 9), List.of()));
        assertThat(rows.get(1).get(0)).isEqualTo("Цены на 09.11.2026");
        assertThat(rows.toString()).contains("Товаров с ценой пока нет");
    }
}
