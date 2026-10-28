import 'dart:io';

import 'package:distribution_mobile/data/agent_data.dart';
import 'package:distribution_mobile/data/local_store.dart';
import 'package:distribution_mobile/data/order.dart';
import 'package:distribution_mobile/data/track.dart';
import 'package:distribution_mobile/data/visit.dart';
import 'package:distribution_mobile/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_server.dart';

void main() {
  test('маршруты дня и магазины по порядку обхода', () {
    final now = DateTime(2026, 10, 28); // среда
    final data = AgentData.fromJson(sampleAgentData(now: now));

    expect(data.routesOn(3).map((r) => r.name), ['Центр']);
    expect(data.routesOn(4).map((r) => r.name), ['Сайрам']);
    expect(data.routesOn(1), isEmpty);
    expect(data.outletsOf(data.routesOn(3).single).map((o) => o.name), ['Магазин «Береке»', 'Магазин «Арай»']);
    expect(data.outlets[1]!.debt, 45000);
    expect(data.product(1)!.priceFor('RETAIL'), 600);
    expect(data.product(1)!.priceFor('WHOLESALE'), 500);
    expect(data.settings.visitRadius, 200);
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

  test('SQLite: заказы — ждут отправки, ответ сервера, стирание отправленного', () async {
    sqfliteFfiInit();
    final store = await SqliteStore.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final o = Order(
        uuid: 'з1', visitUuid: 'в1', outletId: 2, createdAt: DateTime(2026, 10, 28, 10, 5),
        deliveryDate: DateTime(2026, 10, 29), payment: 'KASPI', comment: 'после обеда', items: {1: 12, 2: 20},
        total: 12000);
    await store.saveOrder(o);
    expect(await store.unsentCount(), 1);
    final back = (await store.ordersToSend()).single;
    expect(back.toJson(), {
      'uuid': 'з1', 'visitUuid': 'в1', 'outletId': 2, 'createdAt': '2026-10-28T10:05:00', 'deliveryDate': '2026-10-29',
      'payment': 'KASPI', 'comment': 'после обеда', 'items': [{'productId': 1, 'qty': 12}, {'productId': 2, 'qty': 20}],
    });

    back.takeServer({'number': 'З-281026-4', 'status': 'ACCEPTED', 'statusLabel': 'Принят', 'note': null, 'total': 12500});
    await store.saveOrder(back);
    expect(await store.unsentCount(), 0);
    final saved = (await store.ordersSince(DateTime(2026, 10, 28))).single;
    expect([saved.number, saved.statusLabel, saved.total], ['З-281026-4', 'Принят', 12500]);

    await store.pruneOrders(DateTime(2026, 10, 28));
    expect(await store.ordersSince(DateTime(2000)), hasLength(1));
    await store.pruneOrders(DateTime(2026, 11, 1));
    expect(await store.ordersSince(DateTime(2000)), isEmpty);

    await store.write('order-draft', {'visit': 'в1'});
    await store.remove('order-draft');
    expect(await store.read('order-draft'), isNull);
    await store.close();
  });
}

