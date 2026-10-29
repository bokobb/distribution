import 'dart:io';

import 'package:distribution_mobile/data/agent_data.dart';
import 'package:distribution_mobile/data/local_store.dart';
import 'package:distribution_mobile/data/new_outlet.dart';
import 'package:distribution_mobile/data/order.dart';
import 'package:distribution_mobile/data/track.dart';
import 'package:distribution_mobile/data/visit.dart';
import 'package:distribution_mobile/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_server.dart';

void main() {
  test('данные агента: товары с ценами, маршрут магазина, сводка для карты', () {
    final now = DateTime(2026, 10, 28);
    final data = AgentData.fromJson(sampleAgentData(now: now));

    expect(data.outlets[1]!.debt, 45000);
    expect(data.product(1)!.priceFor('RETAIL'), 600);
    expect(data.product(1)!.priceFor('WHOLESALE'), 500);
    expect(data.settings.visitRadius, 200);
    expect(data.routeOf(3)?.name, 'Сайрам');
    expect([data.stats[1]!.lastVisit, data.stats[1]!.avgOrder], [DateTime(2026, 10, 27), 30400]);
    expect(data.stats[3]!.lastVisit, isNull);
    expect(data.stats[12]!.createdOn, DateTime(2026, 10, 24));

    // старые данные на телефоне — без others и сводки
    final old = AgentData.fromJson(sampleAgentData()
      ..remove('others')
      ..remove('stats'));
    expect([old.others, old.stats], [isEmpty, isEmpty]);
  });

  test('новый магазин с телефона: в базе с номером телефона, после приёма — с номером сервера', () {
    final data = AgentData.fromJson(sampleAgentData());
    final fresh = NewOutlet(
        uuid: 'n-1', createdAt: DateTime(2026, 10, 28, 10, 5), name: 'Магазин «Береке-2»', phone: '+77011234567',
        address: 'ул. Сейфуллина, 40', lat: 42.3, lng: 69.6, priceKind: 'RETAIL');
    final rejected = NewOutlet(
        uuid: 'n-2', createdAt: DateTime(2026, 10, 28, 10, 6), name: 'Отклонён', phone: '+77011234568', error: 'Дубль');

    final local = data.withLocal([fresh, rejected]);
    expect(fresh.localId, isNegative);
    expect(local.base.map((o) => o.id), [1, 2, 3, 10, 11, 12, fresh.localId]);
    final o = local.outlet(fresh.localId)!;
    expect([o.name, o.mine, o.pending, o.debt, o.priceKind], ['Магазин «Береке-2»', true, true, 0, 'RETAIL']);
    expect(data.base, hasLength(6), reason: 'исходные данные не меняются');

    // сервер принял, данные ещё старые — номер сервера, по номеру телефона тоже находится
    fresh.serverId = 100;
    final accepted = data.withLocal([fresh]);
    expect(accepted.base.last.id, 100);
    expect(accepted.outlet(fresh.localId)!.id, 100);

    // данные обновились — магазин уже с сервера, без дубля
    final json = sampleAgentData();
    (json['outlets'] as List).add({...(json['outlets'] as List).first as Map<String, dynamic>, 'id': 100, 'name': 'С сервера'});
    final synced = AgentData.fromJson(json).withLocal([fresh]);
    expect(synced.base.where((o) => o.id == 100).map((o) => o.name), ['С сервера']);
    expect(synced.outlet(fresh.localId)!.name, 'С сервера');
  });

  test('вся база: свои с долгами, чужие без долгов и с прайсом; последний заказ магазина', () {
    final data = AgentData.fromJson(sampleAgentData());

    expect(data.base.map((o) => o.id), [1, 2, 3, 10, 11, 12]);
    final sosed = data.outlet(10)!;
    expect([sosed.mine, sosed.debt, sosed.owner, sosed.priceKind], [false, 0, 'Гульнара М.', 'RETAIL']);
    expect(data.outlet(12)!.pending, isTrue);
    expect([data.outlet(1)!.mine, data.outlet(1)!.debt], [true, 45000]);
    expect(data.outlet(99), isNull);

    final last = data.lastOrders[1]!;
    expect([last.date, last.items], [DateTime(2026, 10, 21), {1: 24, 2: 40}]);
    expect(data.lastOrders[2], isNull);

    // старые данные: у чужих только точка, прайс — опт
    final old = sampleAgentData();
    old.remove('lastOrders');
    for (final p in (old['others'] as List).cast<Map<String, dynamic>>()) {
      p.remove('owner');
      p.remove('priceKind');
      p.remove('status');
    }
    final o = AgentData.fromJson(old);
    expect([o.outlet(10)!.priceKind, o.outlet(10)!.status, o.lastOrders], ['WHOLESALE', 'ACTIVE', isEmpty]);
  });

  test('подписи: деньги, склонения, когда обновлено', () {
    expect(money(45000), '45 000 ₸');
    expect(money(-500), '−500 ₸');
    expect(money(1234567), '1 234 567 ₸');
    expect(plural(1, 'магазин', 'магазина', 'магазинов'), '1 магазин');
    expect(plural(3, 'магазин', 'магазина', 'магазинов'), '3 магазина');
    expect(plural(12, 'магазин', 'магазина', 'магазинов'), '12 магазинов');
    expect(plural(21, 'магазин', 'магазина', 'магазинов'), '21 магазин');
    final now = DateTime(2026, 10, 28, 12);
    expect(when(DateTime(2026, 10, 28, 9, 5), now: now), 'сегодня в 09:05');
    expect(when(DateTime(2026, 10, 27, 18, 0), now: now), 'вчера в 18:00');
    expect(when(DateTime(2026, 10, 25, 8, 30), now: now), '25.10 в 08:30');
  });

  test('SQLite на телефоне: сохранить, прочитать, стереть при выходе', () async {
    sqfliteFfiInit();
    final store = await SqliteStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);

    expect(await store.read('agent'), isNull);
    await store.write('agent', {'a': 1});
    await store.write('agent', {'a': 2});
    expect(await store.read('agent'), {'a': 2});
    await store.clear();
    expect(await store.read('agent'), isNull);
    await store.close();
  });

  test('SQLite: журнал и точки ждут отправки, отправленное помечается', () async {
    sqfliteFfiInit();
    final store = await SqliteStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final start = DateTime(2026, 10, 28, 8, 40);
    await store.addEvent(TrackEvent(uuid: 'u1', at: start, kind: 'DAY_START'));
    await store.addPoint(TrackPoint(at: start.add(const Duration(minutes: 1)), lat: 42.3, lng: 69.6, accuracy: 10, battery: 80));
    await store.addPoint(TrackPoint(at: start.add(const Duration(minutes: 1)), lat: 42.3, lng: 69.6)); // та же точка
    await store.addPoint(TrackPoint(at: start.add(const Duration(minutes: 6)), lat: 42.31, lng: 69.61));

    expect(await store.unsentCount(), 3);
    final first = await store.unsent(2);
    expect(first.events.single.kind, 'DAY_START');
    expect(first.points.single.accuracy, 10);
    await store.markSent(first);
    expect(await store.unsentCount(), 1);
    expect((await store.unsent(10)).points.single.lat, 42.31);
    // отправленное остаётся видно: по нему открыт ли рабочий день
    expect((await store.eventsSince(DateTime(2026, 10, 28))).single.uuid, 'u1');
    await store.clear();
    expect(await store.unsentCount(), 0);
    await store.close();
  });

  test('SQLite: визиты — идущий, ждущие отправки, фото, стирание отправленного', () async {
    sqfliteFfiInit();
    final store = await SqliteStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final today = DateTime(2026, 10, 28);
    final yesterday = Visit(uuid: 'вчера', outletId: 1, startedAt: today.subtract(const Duration(hours: 5)));
    final done = Visit(
        uuid: 'утро', outletId: 2, routeId: 1, startedAt: today.add(const Duration(hours: 9)), lat: 42.3, lng: 69.6,
        accuracy: 12, distance: 35, photo: '/фото/утро.jpg')
      ..finishedAt = today.add(const Duration(hours: 9, minutes: 7))
      ..result = 'NO_ORDER'
      ..reason = 'Нет денег';
    await store.saveVisit(yesterday);
    await store.saveVisit(done);

    // незаконченный вчерашний виден, чтобы его закончить или отменить; не отправляется
    expect((await store.visitsSince(today)).map((v) => v.uuid), ['вчера', 'утро']);
    final toSend = await store.visitsToSend();
    expect(toSend.single.toJson(), {
      'uuid': 'утро', 'outletId': 2, 'routeId': 1, 'startedAt': '2026-10-28T09:00:00',
      'finishedAt': '2026-10-28T09:07:00', 'lat': 42.3, 'lng': 69.6, 'result': 'NO_ORDER', 'refuseReason': 'Нет денег',
    });
    expect(await store.unsentCount(), 2); // визит и фото

    done.sent = true;
    await store.saveVisit(done);
    expect(await store.unsentCount(), 1);
    expect(await store.pruneVisits(today.add(const Duration(days: 4))), isEmpty); // фото ещё не ушло
    done.photoSent = true;
    await store.saveVisit(done);
    expect(await store.unsentCount(), 0);
    expect(await store.pruneVisits(today), isEmpty); // свежий — держим
    expect(await store.pruneVisits(today.add(const Duration(days: 4))), ['/фото/утро.jpg']);
    expect((await store.visitsSince(today)).map((v) => v.uuid), ['вчера']);

    await store.deleteVisit('вчера');
    expect(await store.visitsSince(DateTime(2000)), isEmpty);
    await store.close();
  });

  test('SQLite: база версии 2 обновляется — визиты появляются, журнал на месте', () async {
    sqfliteFfiInit();
    final path = '${Directory.systemTemp.createTempSync('db').path}/v2.db';
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, _) async {
              await db.execute('create table snapshot (key text primary key, json text not null, saved_at text not null)');
              await db.execute('create table journal (uuid text primary key, at text not null, kind text not null, '
                  'note text, sent integer not null default 0)');
              await db.execute('create table gps (at text primary key, lat real not null, lng real not null, '
                  'accuracy integer, battery integer, sent integer not null default 0)');
              await db.insert('journal', {'uuid': 'u1', 'at': '2026-10-28T08:40:00.000', 'kind': 'DAY_START'});
            }));
    await old.close();

    final store = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    expect(await store.unsentCount(), 1);
    await store.saveVisit(Visit(uuid: 'в', outletId: 1, startedAt: DateTime(2026, 10, 28, 9)));
    expect((await store.visitsSince(DateTime(2026, 10, 28))).single.uuid, 'в');
    await store.close();
  });

  test('SQLite: заказы с возвратом — ждут отправки, ответ сервера, стирание отправленного', () async {
    sqfliteFfiInit();
    final store = await SqliteStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final o = Order(
        uuid: 'з1', visitUuid: 'в1', outletId: 2, createdAt: DateTime(2026, 10, 28, 10, 5),
        deliveryDate: DateTime(2026, 10, 29), payment: 'KASPI', comment: 'после обеда', items: {1: 12, 2: 20},
        total: 12000, returns: const [ReturnItem(productId: 2, qty: 3, reason: 'EXPIRED')], returnTotal: 1500);
    await store.saveOrder(o);
    expect(await store.unsentCount(), 1);
    final back = (await store.ordersToSend()).single;
    expect(back.toJson(), {
      'uuid': 'з1', 'visitUuid': 'в1', 'outletId': 2, 'createdAt': '2026-10-28T10:05:00', 'deliveryDate': '2026-10-29',
      'payment': 'KASPI', 'comment': 'после обеда', 'items': [{'productId': 1, 'qty': 12}, {'productId': 2, 'qty': 20}],
      'returns': [{'productId': 2, 'qty': 3, 'reason': 'EXPIRED'}],
    });
    expect([back.returnTotal, back.toPay], [1500, 10500]);

    back.takeServer({'number': 'З-281026-4', 'status': 'ACCEPTED', 'statusLabel': 'Принят', 'note': null, 'total': 12500,
        'returnTotal': 1600});
    await store.saveOrder(back);
    expect(await store.unsentCount(), 0);
    final saved = (await store.ordersSince(DateTime(2026, 10, 28))).single;
    expect([saved.number, saved.statusLabel, saved.total, saved.returnTotal, saved.returns.single.reasonLabel],
        ['З-281026-4', 'Принят', 12500, 1600, 'Срок годности']);

    await store.pruneOrders(DateTime(2026, 10, 28));
    expect(await store.ordersSince(DateTime(2000)), hasLength(1));
    await store.pruneOrders(DateTime(2026, 11, 1));
    expect(await store.ordersSince(DateTime(2000)), isEmpty);

    await store.write('order-draft', {'visit': 'в1'});
    await store.remove('order-draft');
    expect(await store.read('order-draft'), isNull);
    await store.close();
  });

  test('SQLite: новые магазины — ждут отправки, фото, непринятые, стирание отправленного', () async {
    sqfliteFfiInit();
    final store = await SqliteStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final o = NewOutlet(
        uuid: 'н1', createdAt: DateTime(2026, 10, 28, 11), routeId: 2, name: 'Магазин «Нур»', bin: '123456789012',
        phone: '+7 701 555 44 33', address: 'ул. Абая, 5', lat: 42.31, lng: 69.59, accuracy: 9, priceKind: 'RETAIL',
        photo: '/фото/н1.jpg');
    await store.saveNewOutlet(o);
    expect(await store.unsentCount(), 2);
    var p = await store.pending();
    expect([p.outlets, p.photos], [1, 1]);
    final back = (await store.newOutlets()).single;
    expect(back.toJson(), o.toJson());
    expect([back.accuracy, back.photo], [9, '/фото/н1.jpg']);

    back.sent = true;
    await store.saveNewOutlet(back);
    expect(await store.unsentCount(), 1);
    expect(await store.pruneNewOutlets(DateTime(2026, 11, 1)), isEmpty); // фото ещё не ушло
    back.photoSent = true;
    await store.saveNewOutlet(back);
    expect(await store.unsentCount(), 0);

    await store.saveNewOutlet(NewOutlet(
        uuid: 'н2', createdAt: DateTime(2026, 10, 28, 12), name: 'Киоск', phone: '87015554433', landmark: 'остановка')
      ..error = 'Нет маршрута');
    p = await store.pending();
    expect(p.total, 0);
    expect(p.rejectedOutlets.single.error, 'Нет маршрута');

    expect(await store.pruneNewOutlets(DateTime(2026, 10, 28)), isEmpty);
    expect(await store.pruneNewOutlets(DateTime(2026, 11, 1)), ['/фото/н1.jpg']);
    expect((await store.newOutlets()).map((n) => n.uuid), ['н2']);
    await store.deleteNewOutlet('н2');
    expect(await store.newOutlets(), isEmpty);
    await store.close();
  });

  test('SQLite: база версии 8 обновляется — у заказов появляется возврат, старые заказы на месте', () async {
    sqfliteFfiInit();
    final path = '${Directory.systemTemp.createTempSync('db').path}/v8.db';
    var store = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('drop table orders');
    await db.execute('create table orders (uuid text primary key, visit_uuid text, outlet_id integer not null, '
        'created_at text not null, delivery_date text not null, payment text not null, comment text, '
        'items text not null, total integer not null, sent integer not null default 0, error text, number text, '
        'status text, status_label text, note text)');
    await db.insert('orders', {
      'uuid': 'старый', 'outlet_id': 1, 'created_at': '2026-10-28T10:00:00.000', 'delivery_date': '2026-10-29T00:00:00.000',
      'payment': 'CASH', 'items': '{"1":2}', 'total': 1000,
    });
    await db.setVersion(8);
    await db.close();

    store = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    final old = (await store.ordersToSend()).single;
    expect([old.uuid, old.returns, old.returnTotal], ['старый', isEmpty, 0]);
    await store.saveOrder(Order(
        uuid: 'новый', outletId: 1, createdAt: DateTime(2026, 10, 29, 9), deliveryDate: DateTime(2026, 10, 30),
        payment: 'CASH', items: {1: 1}, total: 500, returns: const [ReturnItem(productId: 1, qty: 1, reason: 'DEFECT')],
        returnTotal: 500));
    expect((await store.ordersToSend()).last.returns.single.reason, 'DEFECT');
    await store.close();
  });

  test('SQLite: база версии 4 обновляется — появляются новые магазины, заказы на месте', () async {
    sqfliteFfiInit();
    final path = '${Directory.systemTemp.createTempSync('db').path}/v4.db';
    var store = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    await store.saveOrder(Order(
        uuid: 'з1', outletId: 1, createdAt: DateTime(2026, 10, 28, 10), deliveryDate: DateTime(2026, 10, 29),
        payment: 'CASH', items: {1: 1}, total: 500));
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('drop table new_outlets');
    await db.execute('drop table deliveries');
    await db.execute('drop table debt_payments');
    await db.execute('drop table defect_returns');
    await db.setVersion(4);
    await db.close();

    store = await SqliteStore.open(path: path, factory: databaseFactoryFfi);
    expect(await store.unsentCount(), 1);
    await store.saveNewOutlet(NewOutlet(uuid: 'н', createdAt: DateTime(2026, 10, 28), name: 'М', phone: '7011234567'));
    expect(await store.unsentCount(), 2);
    await store.close();
  });
}
