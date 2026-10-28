import 'dart:io';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/data/order.dart';
import 'package:distribution_mobile/data/track.dart';
import 'package:distribution_mobile/data/visit.dart';
import 'package:distribution_mobile/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';
import 'memory_store.dart';

void main() {
  late FakeServer server;
  late MemoryStore store;
  final now = DateTime(2026, 10, 28, 10, 5);

  Outbox outbox({Duration retry = const Duration(minutes: 1)}) => Outbox(
      api: ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ'),
      store: store,
      retry: retry,
      clock: () => now);

  Visit visit(String uuid, {String? error, String? photo}) => Visit(
      uuid: uuid, outletId: 1, startedAt: now, finishedAt: now, result: 'NO_ORDER', reason: 'Нет денег', photo: photo)
    ..error = error;

  setUp(() {
    server = FakeServer();
    store = MemoryStore();
  });

  test('нет сети — почему не ушло; сеть есть — когда ушло', () async {
    final o = outbox();
    await store.addEvent(TrackEvent(uuid: 'e1', at: now, kind: 'APP_OPEN'));
    server.offline = true;
    await o.flush();
    expect(o.lastError, 'Нет связи с сервером');
    expect(o.lastOk, isNull);
    expect(o.unsent, 1);

    server.offline = false;
    await o.flush();
    expect(o.lastError, isNull);
    expect(o.lastOk, now);
    expect(o.unsent, 0);
  });

  test('повтор сам: раз в retry, пока есть что отправить', () async {
    final o = outbox(retry: const Duration(milliseconds: 20))..start();
    addTearDown(o.dispose);
    server.offline = true;
    await store.saveVisit(visit('в1'));
    await o.flush();
    expect(o.unsent, 1);

    server.offline = false;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(server.visits.keys, ['в1']);
    expect(o.unsent, 0);
  });

  test('что ждёт и что сервер не принял; непринятое убирается с телефона вместе с фото', () async {
    final o = outbox();
    final photo = File('${Directory.systemTemp.createTempSync('photo').path}/в2.jpg')..writeAsBytesSync([0xFF, 0xD8]);
    await store.addEvent(TrackEvent(uuid: 'e1', at: now, kind: 'DAY_START'));
    await store.saveVisit(visit('в1', photo: '/нет/такого.jpg'));
    await store.saveVisit(visit('в2', error: 'Магазин не найден', photo: photo.path));
    final rejected = Order(
        uuid: 'з2', outletId: 1, createdAt: now, deliveryDate: now, payment: 'CASH', items: {1: 2}, total: 1000)
      ..error = 'Нет цены';
    await store.saveOrder(rejected);
    await store.saveOrder(Order(
        uuid: 'з1', outletId: 1, createdAt: now, deliveryDate: now, payment: 'CASH', items: {1: 1}, total: 500));

    final p = await store.pending();
    expect([p.track, p.visits, p.photos, p.orders, p.total], [1, 1, 1, 1, 4]);
    expect(p.rejectedVisits.single.uuid, 'в2');
    expect(p.rejectedOrders.single.error, 'Нет цены');

    await o.dropVisit(p.rejectedVisits.single);
    await o.dropOrder(p.rejectedOrders.single);
    expect(photo.existsSync(), isFalse);
    final after = await store.pending();
    expect(after.rejectedVisits, isEmpty);
    expect(after.rejectedOrders, isEmpty);
    expect(after.total, 4);
  });
}
