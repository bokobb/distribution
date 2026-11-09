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
 * «Скачать прайс» в «Товарах» (09.11.2026): компания и дата, активные товары по группам — цена CRM, цена продажи
 * и наценка, как в таблице на странице. Нет цены — ячейка пустая.
 */
@Component
public class PriceListXlsx {

    public static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd.MM.yyyy");
    private static final String[] HEAD = {"Товар", "Цена CRM, ₸", "Цена продажи, ₸", "Наценка"};

    /** Товары, которые попадут в прайс: активные, по группам и названию. */
    public static List<Product> rows(List<Product> products) {
        return products.stream().filter(Product::isActive)
                .sorted(Comparator.comparing(Product::getCategory).thenComparing(Product::getName)).toList();
    }

    public byte[] write(String company, LocalDate day, List<Product> products) {
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
            CellStyle money = box(wb, null, plain, HorizontalAlignment.RIGHT);
            money.setDataFormat(wb.createDataFormat().getFormat("# ##0"));
            CellStyle pct = box(wb, null, plain, HorizontalAlignment.RIGHT);
            pct.setDataFormat(wb.createDataFormat().getFormat("0%;[Red]-0%")); // в минусе — красным, как на странице
            int last = HEAD.length - 1;

            Row r0 = ws.createRow(0);
            Cell c0 = r0.createCell(0);
            c0.setCellValue("Прайс — " + company);
            c0.setCellStyle(title);
            ws.addMergedRegion(new CellRangeAddress(0, 0, 0, last));
            put(ws.createRow(1), 0, "Цены на " + DAY.format(day), sub);

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
                    n++;
                    put(x, 0, p.getName(), text);
                    put(x, 1, p.getCrmPrice() == null || p.getCrmPrice() == 0 ? null : p.getCrmPrice(), money);
                    put(x, 2, p.getPrice() == 0 ? null : p.getPrice(), money);
                    put(x, 3, p.getMarkup() == null ? null : p.getMarkup() / 100.0, pct);
                }
            }
            if (n == 0) put(ws.createRow(ri++), 0, "Товаров пока нет", sub);
            put(ws.createRow(ri + 1), 0, "Цены в тенге за штуку, наценка — над ценой CRM. Пусто — цены нет.", sub);

            int[] widths = {46, 14, 16, 11};
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
