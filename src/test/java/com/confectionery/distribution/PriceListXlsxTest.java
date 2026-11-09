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
    void ценаCrm_ценаПродажи_наценка_выключенныхНет() throws Exception {
        Product noCrm = product("Медовик", "Вафли", 1, 3500, true).setCrmPrice(null);
        List<Product> list = List.of(
                product("Шоколадное", "Печенье", 10, 1250, true).setCrmPrice(1000L),
                product("Овсяное", "Печенье", 12, 900, true).setCrmPrice(950L),
                product("Вафли без цены", "Вафли", 6, 0, true).setCrmPrice(400L),
                noCrm,
                product("Старый торт", "Торты", 1, 5000, false));

        List<List<String>> rows = sheet(new PriceListXlsx().write("Олимжон", LocalDate.of(2026, 11, 9), list));

        assertThat(rows.get(0).get(0)).isEqualTo("Прайс — Олимжон");
        assertThat(rows.get(1)).containsExactly("Цены на 09.11.2026");
        assertThat(rows.get(3)).containsExactly("Товар", "Цена CRM, ₸", "Цена продажи, ₸", "Наценка");
        assertThat(rows.subList(4, 10)).containsExactly(
                List.of("Вафли", "", "", ""),
                List.of("Вафли без цены", "400", "", ""),
                List.of("Медовик", "", "3 500", ""),
                List.of("Печенье", "", "", ""),
                List.of("Овсяное", "950", "900", "-5%"),
                List.of("Шоколадное", "1 000", "1 250", "25%"));
        assertThat(rows.toString()).doesNotContain("Старый торт").doesNotContain("коробк");
        assertThat(PriceListXlsx.rows(list)).hasSize(4);
    }

    @Test
    void пустойПрайс() throws Exception {
        List<List<String>> rows = sheet(new PriceListXlsx().write("Олимжон", LocalDate.of(2026, 11, 9), List.of()));
        assertThat(rows.get(1)).containsExactly("Цены на 09.11.2026");
        assertThat(rows.toString()).contains("Товаров пока нет");
    }
}
