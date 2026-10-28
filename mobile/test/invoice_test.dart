import 'package:distribution_mobile/data/delivery.dart';
import 'package:distribution_mobile/data/expeditor_data.dart';
import 'package:distribution_mobile/format.dart';
import 'package:distribution_mobile/invoice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = ExpeditorData.fromJson(sampleExpeditorData(now: DateTime(2026, 10, 28)));
  final trip = data.current.single;
  final arai = trip.stops.first, bereke = trip.stops.last;

  test('сумма прописью — как в админке', () {
    expect(moneyWords(112440), 'Сто двенадцать тысяч четыреста сорок тенге');
    expect(moneyWords(0), 'Ноль тенге');
    expect(moneyWords(1), 'Один тенге');
    expect(moneyWords(11), 'Одиннадцать тенге');
    expect(moneyWords(21000), 'Двадцать одна тысяча тенге');
    expect(moneyWords(2000000), 'Два миллиона тенге');
    expect(moneyWords(1001500), 'Один миллион одна тысяча пятьсот тенге');
  });

  test('до выдачи — предварительная по заказу, без денег', () {
    final i = Invoice.of(data: data, trip: trip, stop: arai, expeditor: 'Иван');
    expect(i.preliminary, isTrue);
    expect(i.title, 'Накладная № З-271026-1 от 28.10.2026');
    expect(i.fileName, 'Накладная З-271026-1.pdf');
    expect(i.meta, 'Оплата: Наличные · торговый: Айгерим · экспедитор: Иван, рейс Р-281026-1');
    expect([i.supplier, i.supplierPhone], ['Своя доставка', '+7 700 000 01 00']);
    expect(i.buyer, 'ИП Магазин «Арай» (Магазин «Арай»)');
    expect(i.buyerNote, 'ул. Байтурсынова, 1 · +77010000000');
    expect([for (final l in i.lines) '${l.name} ${l.qty}×${l.price}'], ['Печенье овсяное 24×500', 'Вафли сливочные 5×300']);
    expect([i.qty, i.total], [29, 13500]);
    expect(i.payments, isNull);
  });

  test('выдано частично с телефона — по выданному, деньги и остаток в долг', () {
    final d = Delivery(
        uuid: 'в', orderId: 11, tripId: 1, outletId: 1, deliveredAt: DateTime(2026, 10, 28, 11, 20), items: {1: 22, 2: 0},
        total: 11000, cash: 8000, kaspi: 2000, cashUuid: 'н', kaspiUuid: 'к');
    final i = Invoice.of(data: data, trip: trip, stop: arai, local: d);
    expect(i.preliminary, isFalse);
    expect(i.lines.map((l) => l.qty), [22]); // невыданное — не в накладной
    expect(i.total, 11000);
    expect(i.payments, 'Получено наличными ${money(8000)}, Kaspi ${money(2000)} · в долг ${money(1000)}');

    final refused = Delivery(
        uuid: 'о', orderId: 11, tripId: 1, outletId: 1, deliveredAt: DateTime(2026, 10, 28, 11, 20),
        refuseReason: 'Закрыто', cashUuid: 'н', kaspiUuid: 'к');
    expect(Invoice.of(data: data, trip: trip, stop: arai, local: refused).preliminary, isTrue);
  });

  test('выдано по данным сервера — выданное количество, в долг', () {
    final i = Invoice.of(data: data, trip: trip, stop: bereke);
    expect(i.preliminary, isFalse);
    expect(i.total, 5000);
    expect(i.payments, 'в долг ${money(5000)}');
  });

  test('PDF собирается со шрифтом приложения', () async {
    final bytes = await Invoice.of(data: data, trip: trip, stop: arai).pdf();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10000));
  });
}
