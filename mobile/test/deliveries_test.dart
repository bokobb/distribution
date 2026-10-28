import 'dart:io';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/data/delivery.dart';
import 'package:distribution_mobile/data/expeditor_data.dart';
import 'package:distribution_mobile/data/local_store.dart';
import 'package:distribution_mobile/deliveries.dart';
import 'package:distribution_mobile/outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    book = DeliveryBook(store: store, outbox: outbox, location: gps, clock: () => now);
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
    expect(outbox.deliveriesSent, 1);
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

  test('повтор отправки той же выдачи не задваивает: uuid выдачи и оплат те же', () async {
    await book.deliver(trip(), arai(), items: {1: 24, 2: 5}, cash: 13500, settings: data.settings);
    await settle();
    final d = book.of(11)!;
    final again = Delivery.decode(d.encode());
    expect(again.toJson(), d.toJson());
    expect(again.cashUuid, d.cashUuid);
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
