import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'data/delivery.dart';
import 'data/expeditor_data.dart';
import 'format.dart';

/// Строка накладной: сколько штук по какой цене.
class InvoiceLine {
  const InvoiceLine({required this.name, required this.unit, required this.qty, required this.price});

  final String name;
  final String unit;
  final int qty;
  final int price;

  int get sum => qty * price;
}

/// Накладная на заказ точки — как в админке: поставщик, покупатель, товары, итого, сумма прописью, подписи. Выдано —
/// по выданному (с телефона или с сервера) и с деньгами; ещё нет — предварительная по заказу. Печатают в офисе,
/// с телефона — посмотреть и отправить магазину PDF.
class Invoice {
  Invoice._(
      {required this.number,
      required this.day,
      required this.preliminary,
      required this.meta,
      required this.supplier,
      this.supplierPhone,
      required this.buyer,
      this.buyerNote,
      required this.lines,
      this.cash = 0,
      this.kaspi = 0,
      this.paid = 0});

  factory Invoice.of(
      {required ExpeditorData data, required TripInfo trip, required Stop stop, Delivery? local, String? expeditor}) {
    final order = stop.order, o = stop.outlet;
    final d = local != null && local.error == null && !local.refused ? local : null;
    final delivered = d != null || order.done && !order.refused;
    final lines = [
      for (final l in order.lines)
        InvoiceLine(
          name: l.name,
          unit: l.unit,
          qty: d != null
              ? d.items.isEmpty
                  ? l.qty
                  : d.items[l.productId] ?? 0
              : delivered
                  ? l.delivered ?? l.qty
                  : l.qty,
          price: l.price,
        ),
    ].where((l) => l.qty > 0).toList();
    return Invoice._(
      number: order.number,
      day: d?.deliveredAt ?? (delivered ? data.date : order.deliveryDate),
      preliminary: !delivered,
      meta: [
        'Оплата: ${order.paymentLabel}',
        if (order.agent != null) 'торговый: ${order.agent}',
        [if (expeditor != null) 'экспедитор: $expeditor', 'рейс ${trip.number}'].join(', '),
      ].join(' · '),
      supplier: data.companyName ?? '',
      supplierPhone: data.companyPhone,
      buyer: o.legal != null && o.legal!.isNotEmpty ? '${o.legal} (${o.name})' : o.name,
      buyerNote: [if (o.address != null) o.address!, if (o.phone != null) o.phone!].join(' · '),
      lines: lines,
      cash: d?.cash ?? 0,
      kaspi: d?.kaspi ?? 0,
      paid: d?.paid ?? order.paid,
    );
  }

  final String number;

  /// День выдачи; до выдачи — день доставки по заказу.
  final DateTime day;

  /// Ещё не выдано — по заказу, «предварительная».
  final bool preliminary;

  /// «Оплата: … · торговый: … · экспедитор: …, рейс …».
  final String meta;
  final String supplier;
  final String? supplierPhone;
  final String buyer;
  final String? buyerNote;
  final List<InvoiceLine> lines;

  /// Получено при выдаче (на телефоне — по способам; с сервера — только всего).
  final int cash;
  final int kaspi;
  final int paid;

  int get total => lines.fold(0, (a, l) => a + l.sum);
  int get qty => lines.fold(0, (a, l) => a + l.qty);

  String get title => 'Накладная № $number от ${date(day)}';
  String get fileName => 'Накладная $number.pdf';

  /// «Получено наличными 10 000 ₸, Kaspi 2 000 ₸ · в долг 500 ₸»; до выдачи и без денег — null.
  String? get payments {
    if (preliminary) return null;
    final got = [
      if (cash > 0) 'наличными ${money(cash)}',
      if (kaspi > 0) 'Kaspi ${money(kaspi)}',
      if (cash == 0 && kaspi == 0 && paid > 0) money(paid),
    ];
    final debt = total - paid;
    return [
      if (got.isNotEmpty) 'Получено ${got.join(', ')}',
      if (debt > 0) 'в долг ${money(debt)}',
    ].join(' · ');
  }

  /// PDF А4 со шрифтом приложения (кириллица и «₸»).
  Future<Uint8List> pdf() async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/IBMPlexSans-SemiBold.ttf'));
    const soft = PdfColor.fromInt(0xFF5C5C5C);
    const line = PdfColor.fromInt(0xFF9A9A9A);
    final doc = pw.Document(title: title, author: supplier);
    final pays = payments;
    pw.Widget party(String label, String name, String? note) => pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: soft)),
            pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if (note != null && note.isNotEmpty) pw.Text(note),
          ]),
        );
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 12 * PdfPageFormat.mm,
          marginRight: 12 * PdfPageFormat.mm,
          marginTop: 12 * PdfPageFormat.mm,
          marginBottom: 12 * PdfPageFormat.mm),
      theme: pw.ThemeData.withFont(base: regular, bold: bold)
          .copyWith(defaultTextStyle: pw.TextStyle(font: regular, fontBold: bold, fontSize: 9.5)),
      build: (_) => [
        pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        if (preliminary)
          pw.Text('Предварительная — по заказу, до выдачи',
              style: const pw.TextStyle(color: PdfColor.fromInt(0xFFB9203C))),
        pw.Text(meta, style: const pw.TextStyle(color: soft)),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          party('Поставщик', supplier, supplierPhone == null ? null : 'тел. $supplierPhone'),
          pw.SizedBox(width: 16),
          party('Покупатель', buyer, buyerNote),
        ]),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['№', 'Товар', 'Ед.', 'Кол-во', 'Цена, ₸', 'Сумма, ₸'],
          data: [
            for (var i = 0; i < lines.length; i++)
              [
                '${i + 1}',
                lines[i].name,
                lines[i].unit,
                amount(lines[i].qty),
                amount(lines[i].price),
                amount(lines[i].sum),
              ],
            ['', 'Итого', '', amount(qty), '', amount(total)],
          ],
          border: pw.TableBorder.all(color: line, width: 0.6),
          headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F3F1)),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          columnWidths: {
            0: const pw.FixedColumnWidth(22),
            1: const pw.FlexColumnWidth(),
            2: const pw.FixedColumnWidth(30),
            3: const pw.FixedColumnWidth(50),
            4: const pw.FixedColumnWidth(60),
            5: const pw.FixedColumnWidth(70),
          },
          cellAlignments: {
            0: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
          headerAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 8),
        pw.Text('Всего наименований ${lines.length} на сумму: ${moneyWords(total)}'),
        if (pays != null && pays.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(pays)),
        pw.SizedBox(height: 28),
        pw.Row(children: [
          for (final s in ['Отпустил (подпись, ФИО)', 'Получил (подпись, ФИО)']) ...[
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.only(top: 3),
                decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8))),
                child: pw.Text(s, style: const pw.TextStyle(fontSize: 8, color: soft)),
              ),
            ),
            if (s.startsWith('Отпустил')) pw.SizedBox(width: 24),
          ],
        ]),
      ],
    ));
    return doc.save();
  }
}
