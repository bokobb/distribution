package com.confectionery.distribution.service;

import com.confectionery.distribution.domain.Product;
import org.apache.poi.ss.usermodel.BorderStyle;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.HorizontalAlignment;
import org.apache.poi.ss.usermodel.IndexedColors;
import org.apache.poi.ss.usermodel.PrintSetup;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.VerticalAlignment;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.util.CellRangeAddress;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Component;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

/**
 * «Скачать прайс» в «Товарах» (09.11.2026): прайс для магазинов в Excel — компания и дата, товары по группам,
 * штук в коробке, цена за штуку и за коробку. Только активные товары с ценой; цена CRM и наценка в файл не идут —
 * это внутреннее.
 */
@Component
public class PriceListXlsx {

    public static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd.MM.yyyy");
    private static final String[] HEAD = {"№", "Товар", "В коробке, шт", "Цена за шт, ₸", "Цена за коробку, ₸"};

    /** Товары, которые попадут в прайс: активные, с ценой, по группам и названию. */
    public static List<Product> rows(List<Product> products) {
        return products.stream().filter(p -> p.isActive() && p.getPrice() > 0)
                .sorted(Comparator.comparing(Product::getCategory).thenComparing(Product::getName)).toList();
    }

    public byte[] write(String company, String phone, LocalDate day, List<Product> products) {
        Map<String, List<Product>> byCat = rows(products).stream()
                .collect(Collectors.groupingBy(Product::getCategory, TreeMap::new, Collectors.toList()));
        try (Workbook wb = new XSSFWorkbook(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            Sheet ws = wb.createSheet("Прайс");
            // шрифт явно: без него LibreOffice и телефоны подставляют жирному Calibri моноширинный
            Font plain = font(wb, false, 10);
            Font bold = font(wb, true, 10);
            CellStyle title = wb.createCellStyle();
            title.setFont(font(wb, true, 14));
            CellStyle sub = wb.createCellStyle();
            sub.setFont(plain);
            CellStyle head = box(wb, IndexedColors.GREY_25_PERCENT, bold, HorizontalAlignment.CENTER);
            head.setWrapText(true);
            CellStyle group = box(wb, IndexedColors.GREY_25_PERCENT, bold, HorizontalAlignment.LEFT);
            CellStyle text = box(wb, null, plain, HorizontalAlignment.LEFT);
            CellStyle num = box(wb, null, plain, HorizontalAlignment.CENTER);
            CellStyle money = box(wb, null, plain, HorizontalAlignment.RIGHT);
            money.setDataFormat(wb.createDataFormat().getFormat("# ##0"));
            int last = HEAD.length - 1;

            Row r0 = ws.createRow(0);
            Cell c0 = r0.createCell(0);
            c0.setCellValue("Прайс-лист — " + company);
            c0.setCellStyle(title);
            ws.addMergedRegion(new CellRangeAddress(0, 0, 0, last));
            put(ws.createRow(1), 0, "Цены на " + DAY.format(day) + (phone == null || phone.isBlank() ? "" : " · тел. " + phone), sub);

            Row h = ws.createRow(3);
            for (int i = 0; i < HEAD.length; i++) {
                Cell c = h.createCell(i);
                c.setCellValue(HEAD[i]);
                c.setCellStyle(head);
            }
            int ri = 4, n = 0;
            for (Map.Entry<String, List<Product>> cat : byCat.entrySet()) {
                Row g = ws.createRow(ri);
                for (int i = 0; i <= last; i++) g.createCell(i).setCellStyle(group);
                g.getCell(0).setCellValue(cat.getKey());
                ws.addMergedRegion(new CellRangeAddress(ri, ri, 0, last));
                ri++;
                for (Product p : cat.getValue()) {
                    Row x = ws.createRow(ri++);
                    put(x, 0, ++n, num);
                    put(x, 1, p.getName(), text);
                    put(x, 2, p.getPerBox(), num);
                    put(x, 3, p.getPrice(), money);
                    put(x, 4, p.getPrice() * Math.max(1, p.getPerBox()), money);
                }
            }
            if (n == 0) put(ws.createRow(ri++), 0, "Товаров с ценой пока нет", sub);
            put(ws.createRow(ri + 1), 0, "Цены в тенге, за штуку и за целую коробку.", sub);

            int[] widths = {6, 46, 13, 15, 18};
            for (int i = 0; i < widths.length; i++) ws.setColumnWidth(i, widths[i] * 256);
            ws.createFreezePane(0, 4);
            ws.setRepeatingRows(new CellRangeAddress(3, 3, 0, last));
            ws.setAutobreaks(true);
            ws.setFitToPage(true);
            PrintSetup ps = ws.getPrintSetup();
            ps.setPaperSize(PrintSetup.A4_PAPERSIZE);
            ps.setFitWidth((short) 1);
            ps.setFitHeight((short) 0);
            wb.write(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new IllegalStateException("Не получилось собрать прайс: " + e.getMessage(), e);
        }
    }

    private static void put(Row r, int i, Object v, CellStyle st) {
        Cell c = r.createCell(i);
        if (v instanceof Number x) c.setCellValue(x.doubleValue());
        else c.setCellValue(v == null ? "" : String.valueOf(v));
        c.setCellStyle(st);
    }

    private static Font font(Workbook wb, boolean bold, int size) {
        Font f = wb.createFont();
        f.setFontName("Arial");
        f.setBold(bold);
        f.setFontHeightInPoints((short) size);
        return f;
    }

    private static CellStyle box(Workbook wb, IndexedColors fill, Font font, HorizontalAlignment align) {
        CellStyle s = wb.createCellStyle();
        s.setBorderTop(BorderStyle.THIN);
        s.setBorderBottom(BorderStyle.THIN);
        s.setBorderLeft(BorderStyle.THIN);
        s.setBorderRight(BorderStyle.THIN);
        s.setAlignment(align);
        s.setVerticalAlignment(VerticalAlignment.CENTER);
        if (fill != null) {
            s.setFillForegroundColor(fill.getIndex());
            s.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        }
        if (font != null) s.setFont(font);
        return s;
    }
}
