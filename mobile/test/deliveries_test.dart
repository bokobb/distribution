import 'dart:io';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/data/debt_payment.dart';
import 'package:distribution_mobile/data/defect_return.dart';
import 'package:distribution_mobile/data/delivery.dart';
import 'package:distribution_mobile/data/expeditor_data.dart';
import 'package:distribution_mobile/data/local_store.dart';
import 'package:distribution_mobile/deliveries.dart';
import 'package:distribution_mobile/outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_camera.dart';
import 'fake_location.dart';
import 'fake_server.dart';
import 'memory_store.dart';

void main() {
  late FakeServer server;
  late MemoryStore store;
  late FakeLocation gps;
  late Outbox outbox;
  late DeliveryBook book;
  late ExpeditorData data;
  final now = DateTime(2026, 10, 28, 11, 20);

  TripInfo trip() => data.current.single;

  /// «Арай»: 24 печенья по 500 и 5 вафель по 300, наличными, 13 500 ₸.
  Stop arai() => trip().stops.first;

  setUp(() async {
    server = FakeServer(role: 'EXPEDITOR');
    store = MemoryStore();
    gps = FakeLocation();
    final api = ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ');
    outbox = Outbox(api: api, store: store, clock: () => now);
    book = DeliveryBook(store: store, outbox: outbox, location: gps, camera: FakeCamera(), clock: () => now);
    data = ExpeditorData.fromJson(sampleExpeditorData(now: now));
  });

  tearDown(() {
    book.dispose();
    outbox.dispose();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('выдал всё за наличные — на сервер пустой состав и одна оплата, точка пройдена', () async {
    expect(book.doneIn(trip()), 1);

    expect(await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, cash: 13500, settings: data.settings), isNull);
    expect(book.done(arai().order), isTrue);
    expect(book.doneIn(trip()), 2);
    await settle();

    final sent = server.deliveries.values.single;
    expect(sent['orderId'], 11);
    expect(sent['refused'], false);
    expect(sent['items'], isEmpty);
    expect(sent['deliveredAt'], '2026-10-28T11:20:00');
    expect([sent['lat'], sent['lng']], [42.3, 69.6]);
    final pay = (sent['payments'] as List).single as Map;
    expect([pay['method'], pay['amount']], ['CASH', 13500]);
    expect(pay['uuid'], hasLength(36));
    final d = book.of(11)!;
    expect([d.sent, d.statusLabel, d.unpaid], [true, 'Доставлен', 0]);
    expect(outbox.expeditorSent, 1);
    expect(outbox.unsent, 0);
  });

  test('частично: состав по товарам, часть денег Kaspi, остаток — в долг', () async {
    expect(await book.deliver(trip(), arai(), items: {1: 12, 2: 5}, cash: 2000, kaspi: 5000, settings: data.settings),
        isNull);
    await settle();

    final sent = server.deliveries.values.single;
    expect(sent['items'], [
      {'productId': 1, 'qty': 12},
      {'productId': 2, 'qty': 5},
    ]);
    expect([for (final p in sent['payments'] as List) '${p['method']} ${p['amount']}'], ['CASH 2000', 'KASPI 5000']);
    final d = book.of(11)!;
    expect([d.partial, d.total, d.paid, d.unpaid, d.statusLabel], [true, 7500, 7000, 500, 'Частично']);
  });

  test('проверки: больше заказанного, ничего не выдано, денег больше суммы, Kaspi выключен, уже выдан', () async {
    Future<String?> deliver(Map<int, int> items, {int cash = 0, int kaspi = 0, ExpeditorSettings? settings}) =>
        book.deliver(trip(), arai(), items: items, cash: cash, kaspi: kaspi, settings: settings ?? data.settings);

    expect(await deliver({1: 25, 2: 5}), 'По «Печенье овсяное» можно выдать не больше 24');
    expect(await deliver({1: 0, 2: 0}), 'Ничего не выдано — отметьте отказ');
    expect(await deliver({1: 24, 2: 5}, cash: 13501), 'Получено больше, чем выдано');
    expect(
        await deliver({1: 24, 2: 5},
            kaspi: 100, settings: const ExpeditorSettings(acceptKaspi: false, allowCredit: true, gpsInterval: 5)),
        'Kaspi компания не принимает');
    expect(await book.deliver(trip(), trip().stops.last, items: {1: 10}, settings: data.settings), 'Заказ уже выдан');
    expect(store.deliveriesByUuid, isEmpty);
  });

  test('отказ — с причиной; без причины нельзя', () async {
    expect(await book.refuse(trip(), arai(), '  '), 'Укажите, почему отказ');
    expect(await book.refuse(trip(), arai(), ' Магазин закрыт '), isNull);
    await settle();

    final sent = server.deliveries.values.single;
    expect([sent['refused'], sent['refuseReason'], sent['payments']], [true, 'Магазин закрыт', isEmpty]);
    expect(book.of(11)!.statusLabel, 'Отказ магазина');
    expect(await book.refuse(trip(), arai(), 'Ещё раз'), 'Заказ уже выдан');
  });

  test('без сети: копится на телефоне, отменить можно, пока не ушло; GPS не ответил — без координат', () async {
    server.offline = true;
    gps.here = null;
    await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, settings: data.settings);
    await settle();
    final d = book.of(11)!;
    expect([d.sent, d.lat, d.paid, d.unpaid], [false, null, 0, 13500]);
    expect(outbox.unsent, 1);

    expect(await book.cancel(d), isTrue);
    expect(book.of(11), isNull);
    expect(book.done(arai().order), isFalse);
    expect(outbox.unsent, 0);

    await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, cash: 13500, settings: data.settings);
    await settle();
    server.offline = false;
    await outbox.flush();
    expect(server.deliveries, hasLength(1));
    expect(await book.cancel(book.of(11)!), isFalse); // уже на сервере
    expect(book.of(11), isNotNull);
  });

  test('сервер не принял — точка снова не пройдена, новая выдача заменяет непринятую', () async {
    server.rejectDeliveries = 'Рейс уже закрыт';
    await book.refuse(trip(), arai(), 'Нет денег');
    await settle();
    expect(book.of(11)!.error, 'Рейс уже закрыт');
    expect(book.done(arai().order), isFalse);
    expect((await store.pending()).rejectedDeliveries.single.refuseReason, 'Нет денег');

    server.rejectDeliveries = null;
    await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, cash: 13500, settings: data.settings);
    await settle();
    expect(store.deliveriesByUuid, hasLength(1));
    expect(book.of(11)!.statusLabel, 'Доставлен');
    expect((await store.pending()).rejectedDeliveries, isEmpty);
  });

  test('подтверждение: подпись уходит после выдачи, файл стирается; без сети — ждёт вместе с выдачей', () async {
    final camera = book.camera;
    server.offline = true;
    final png = await camera.keep('подпись.png', [0x89, 0x50, 0x4E, 0x47, 1]);
    await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, cash: 13500, proof: png, settings: data.settings);
    await settle();
    expect(outbox.unsent, 1);
    expect(book.of(11)!.proof, png);

    server.offline = false;
    await outbox.flush();
    final uuid = book.of(11)!.uuid;
    expect(server.proofs[uuid]!.$1, 'image/png');
    expect(server.proofs[uuid]!.$2, [0x89, 0x50, 0x4E, 0x47, 1]);
    expect(File(png).existsSync(), isFalse);
    await settle(); // книга перечитывает телефон после отправки
    expect(book.of(11)!.uploaded, isTrue);
    expect(outbox.unsent, 0);
  });

  test('подтверждение: выдача ушла, а подтверждение — нет (сеть пропала) — дошлётся потом', () async {
    final photo = (await book.camera.photo('накладная'))!;
    server.dropProofs = 1;
    await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, cash: 13500, proof: photo, settings: data.settings);
    await settle();
    final d = book.of(11)!;
    expect([d.sent, d.proofSent, d.uploaded], [true, false, false]);
    expect(outbox.unsent, 1);
    expect(await book.cancel(d), isFalse); // выдача уже на сервере

    await outbox.flush();
    expect(server.proofs[d.uuid]!.$1, 'image/jpeg');
    expect(outbox.unsent, 0);
  });

  test('подтверждение: отменили выдачу до отправки — файл стёрт', () async {
    server.offline = true;
    final png = await book.camera.keep('подпись-2.png', [0x89, 0x50, 0x4E, 0x47]);
    await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, proof: png, settings: data.settings);
    await settle();
    expect(await book.cancel(book.of(11)!), isTrue);
    expect(File(png).existsSync(), isFalse);
  });

  test('повтор отправки той же выдачи не задваивает: uuid выдачи и оплат те же', () async {
    await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, cash: 13500, settings: data.settings);
    await settle();
    final d = book.of(11)!;
    final again = Delivery.decode(d.encode());
    expect(again.toJson(), d.toJson());
    expect(again.cashUuid, d.cashUuid);
  });

  test('оплата долга: наличные и Kaspi — две оплаты, сервер вернул долг; повтор не задваивает', () async {
    expect(await book.payDebt(trip(), arai(), settings: data.settings), 'Введите сумму');
    expect(
        await book.payDebt(trip(), arai(),
            kaspi: 100, settings: const ExpeditorSettings(acceptKaspi: false, allowCredit: true, gpsInterval: 5)),
        'Kaspi компания не принимает');
    expect(await book.payDebt(trip(), arai(), cash: 20000, kaspi: 5000, settings: data.settings), isNull);
    await settle();

    expect([for (final p in server.debtPayments.values) '${p['method']} ${p['amount']} ${p['outletId']} ${p['tripId']}'],
        ['CASH 20000 1 1', 'KASPI 5000 1 1']);
    expect(server.debtPayments.values.first['paidAt'], '2026-10-28T11:20:00');
    final paid = book.paymentsAt(1);
    expect([for (final p in paid) '${p.methodLabel} ${p.sent} ${p.debtAfter}'], ['наличными true 25000', 'Kaspi true 20000']);
    expect(outbox.expeditorSent, 2);

    await outbox.api.debtPayment(paid.first.toJson()); // повтор
    expect(server.debtPayments, hasLength(2));
  });

  test('оплата долга без сети: ждёт, отменить можно; не принятая — с причиной, её можно убрать', () async {
    server.offline = true;
    await book.payDebt(trip(), arai(), cash: 1000, settings: data.settings);
    await settle();
    expect((await store.pending()).debtPayments, 1);
    expect(await book.cancelPayment(book.paymentsAt(1).single), isTrue);
    expect(book.paymentsAt(1), isEmpty);
    expect(outbox.unsent, 0);

    server
      ..offline = false
      ..rejectDebtPayments = 'Рейс уже закрыт';
    await book.payDebt(trip(), arai(), cash: 1000, settings: data.settings);
    await settle();
    final p = book.paymentsAt(1).single;
    expect(p.error, 'Рейс уже закрыт');
    expect(await book.cancelPayment(p), isTrue); // на сервере её нет — убрать можно
    expect(store.debtPaymentsByUuid, isEmpty);
  });

  test('возврат негодного без причины: сервер посчитал сумму и долг; отмена до отправки', () async {
    expect(await book.returnGoods(trip(), arai(), items: {1: 0}, total: 0), 'Выберите товар');

    server.offline = true;
    await book.returnGoods(trip(), arai(), items: {1: 1}, total: 500);
    await settle();
    expect((await store.pending()).returns, 1);
    expect(await book.cancelReturn(book.returnsAt(1).single), isTrue);
    expect(book.returnsAt(1), isEmpty);

    server.offline = false;
    await book.returnGoods(trip(), arai(), items: {1: 3, 2: 2, 3: 0}, total: 1);
    await settle();
    final sent = server.returns.values.single;
    expect(sent['returnedAt'], '2026-10-28T11:20:00');
    expect(sent['lines'], [
      {'productId': 1, 'qty': 3},
      {'productId': 2, 'qty': 2},
    ]);
    final r = book.returnsAt(1).single;
    expect([r.sent, r.total, r.debtAfter, r.qty], [true, 2100, 42900, 5]);
    expect(await book.cancelReturn(r), isFalse);
    expect(outbox.expeditorSent, 1);
  });

  test('SQLite: возвраты — ждут отправки, ответ сервера, непринятые, стирание; база версии 7 обновляется', () async {
    sqfliteFfiInit();
    final path = '${Directory.systemTemp.createTempSync('db').path}/v7.db';
    var db = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    await db.close();
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('drop table defect_returns');
    await raw.setVersion(7);
    await raw.close();

    db = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    final r = DefectReturn(
        uuid: 'в1', outletId: 1, tripId: 1, returnedAt: DateTime(2026, 10, 28, 11, 40), items: {2: 4},
        total: 1200);
    await db.saveReturn(r);
    expect(await db.unsentCount(), 1);
    expect((await db.pending()).returns, 1);
    final back = (await db.returns()).single;
    expect(back.toJson(), r.toJson());
    expect([back.qty, back.total], [4, 1200]);

    back
      ..sent = true
      ..total = 1180
      ..debtAfter = 100;
    await db.saveReturn(back);
    expect(await db.unsentCount(), 0);
    expect((await db.returns()).single.total, 1180);

    await db.saveReturn(DefectReturn(
        uuid: 'в2', outletId: 2, tripId: 1, returnedAt: DateTime(2026, 10, 28, 12), items: {1: 1},
        total: 500)
      ..error = 'Нет цены');
    expect((await db.pending()).rejectedReturns.single.error, 'Нет цены');
    await db.pruneReturns(DateTime(2026, 11, 1));
    expect((await db.returns()).map((x) => x.uuid), ['в2']);
    await db.deleteReturn('в2');
    expect(await db.returns(), isEmpty);
    await db.close();
  });

  test('SQLite: оплаты долга — ждут отправки, ответ сервера, непринятые, стирание; база версии 6 обновляется', () async {
    sqfliteFfiInit();
    final path = '${Directory.systemTemp.createTempSync('db').path}/v6.db';
    var db = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    await db.close();
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('drop table debt_payments');
    await raw.execute('drop table defect_returns');
    await raw.setVersion(6);
    await raw.close();

    db = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    final p = DebtPayment(
        uuid: 'о1', outletId: 1, tripId: 1, method: 'KASPI', amount: 5000, paidAt: DateTime(2026, 10, 28, 11, 30));
    await db.saveDebtPayment(p);
    expect(await db.unsentCount(), 1);
    expect((await db.pending()).debtPayments, 1);
    final back = (await db.debtPayments()).single;
    expect(back.toJson(), {
      'uuid': 'о1', 'outletId': 1, 'tripId': 1, 'method': 'KASPI', 'amount': 5000, 'paidAt': '2026-10-28T11:30:00',
    });

    back
      ..sent = true
      ..debtAfter = -500;
    await db.saveDebtPayment(back);
    expect(await db.unsentCount(), 0);
    expect((await db.debtPayments()).single.debtAfter, -500);

    await db.saveDebtPayment(
        DebtPayment(uuid: 'о2', outletId: 2, tripId: 1, method: 'CASH', amount: 1, paidAt: DateTime(2026, 10, 28, 12))
          ..error = 'Магазина нет в рейсе');
    expect((await db.pending()).rejectedDebtPayments.single.error, 'Магазина нет в рейсе');
    await db.pruneDebtPayments(DateTime(2026, 11, 1));
    expect((await db.debtPayments()).map((x) => x.uuid), ['о2']);
    await db.deleteDebtPayment('о2');
    expect(await db.debtPayments(), isEmpty);
    await db.close();
  });

  test('SQLite: выдачи — ждут отправки, ответ сервера, непринятые, стирание отправленного', () async {
    sqfliteFfiInit();
    final db = await SqliteStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final d = Delivery(
        uuid: 'в1', orderId: 11, tripId: 1, outletId: 1, deliveredAt: DateTime(2026, 10, 28, 11, 20),
        items: {1: 12}, total: 6000, cash: 1000, kaspi: 2000, cashUuid: 'н', kaspiUuid: 'к', lat: 42.3, lng: 69.6);
    await db.saveDelivery(d);
    expect(await db.unsentCount(), 1);
    var p = await db.pending();
    expect(p.deliveries, 1);
    final back = (await db.deliveries()).single;
    expect(back.toJson(), d.toJson());
    expect(back.toJson()['payments'], [
      {'uuid': 'н', 'method': 'CASH', 'amount': 1000},
      {'uuid': 'к', 'method': 'KASPI', 'amount': 2000},
    ]);

    back
      ..sent = true
      ..statusLabel = 'Частично';
    await db.saveDelivery(back);
    expect(await db.unsentCount(), 0);
    expect((await db.deliveries()).single.statusLabel, 'Частично');

    // выдача ушла, подпись — ещё нет: ждёт отправки и не стирается
    final signed = Delivery(
        uuid: 'в3', orderId: 13, tripId: 1, outletId: 3, deliveredAt: DateTime(2026, 10, 20),
        cashUuid: 'н3', kaspiUuid: 'к3', proof: '/tmp/подпись.png')
      ..sent = true;
    await db.saveDelivery(signed);
    expect(await db.unsentCount(), 1);
    await db.pruneDeliveries(DateTime(2026, 10, 28));
    expect((await db.deliveries()).map((x) => x.uuid), contains('в3'));
    expect((await db.deliveries()).firstWhere((x) => x.uuid == 'в3').proof, '/tmp/подпись.png');
    signed.proofSent = true;
    await db.saveDelivery(signed);
    expect(await db.unsentCount(), 0);
    await db.pruneDeliveries(DateTime(2026, 10, 28));
    expect((await db.deliveries()).map((x) => x.uuid), isNot(contains('в3')));

    await db.saveDelivery(Delivery(
        uuid: 'в2', orderId: 12, tripId: 1, outletId: 2, deliveredAt: DateTime(2026, 10, 28, 12),
        refuseReason: 'Закрыто', cashUuid: 'н2', kaspiUuid: 'к2')
      ..error = 'Рейс уже закрыт');
    p = await db.pending();
    expect(p.total, 0);
    expect(p.rejectedDeliveries.single.refuseReason, 'Закрыто');

    await db.pruneDeliveries(DateTime(2026, 10, 28));
    expect(await db.deliveries(), hasLength(2));
    await db.pruneDeliveries(DateTime(2026, 11, 1));
    expect((await db.deliveries()).map((x) => x.uuid), ['в2']); // непринятую — только руками
    await db.deleteDelivery('в2');
    expect(await db.deliveries(), isEmpty);
    await db.close();
  });

  test('SQLite: база версии 5 обновляется — появляются выдачи, новые магазины на месте', () async {
    sqfliteFfiInit();
    final path = '${Directory.systemTemp.createTempSync('db').path}/v5.db';
    var db = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    await db.close();
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('drop table deliveries');
    await raw.execute('drop table debt_payments');
    await raw.execute('drop table defect_returns');
    await raw.setVersion(5);
    await raw.close();

    db = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    await db.saveDelivery(Delivery(
        uuid: 'в', orderId: 11, tripId: 1, outletId: 1, deliveredAt: DateTime(2026, 10, 28), cashUuid: 'н',
        kaspiUuid: 'к'));
    expect(await db.unsentCount(), 1);
    expect(await db.newOutlets(), isEmpty);
    await db.close();
  });
}
