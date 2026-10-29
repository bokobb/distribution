import 'dart:io';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/data/agent_data.dart';
import 'package:distribution_mobile/data/order.dart';
import 'package:distribution_mobile/location.dart';
import 'package:distribution_mobile/outbox.dart';
import 'package:distribution_mobile/visits.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_camera.dart';
import 'fake_location.dart';
import 'fake_server.dart';
import 'memory_store.dart';

void main() {
  late FakeServer server;
  late MemoryStore store;
  late FakeLocation gps;
  late FakeCamera camera;
  late Outbox outbox;
  late VisitBook book;
  late AgentData data;
  final now = DateTime(2026, 10, 28, 10, 5);

  /// Ответ на «Вы далеко от магазина — всё равно начать?»; какие расстояния спрашивали.
  final asked = <int>[];
  Future<bool> yes(int d) async => (asked..add(d)).isNotEmpty;
  Future<bool> no(int d) async => (asked..add(d)).isEmpty;

  setUp(() async {
    server = FakeServer();
    store = MemoryStore();
    gps = FakeLocation();
    camera = FakeCamera();
    outbox = Outbox(api: ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ'), store: store);
    book = VisitBook(store: store, outbox: outbox, location: gps, camera: camera, clock: () => now);
    data = AgentData.fromJson(sampleAgentData(now: now));
    asked.clear();
  });

  tearDown(() => camera.clear());

  Outlet outlet(int id) => data.outlets[id]!;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('рядом с магазином: визит идёт; без заказа — с причиной, уходит на сервер', () async {
    gps.here = Fix(at: now, lat: 42.3009, lng: 69.6, accuracy: 15); // 100 м
    expect(await book.start(outlet(1), routeId: 1, radius: 200, confirmFar: yes), isNull);
    final v = book.current!;
    expect(v.distance, 100);
    expect(book.lastAt(1), same(v));
    expect(await book.start(outlet(2), radius: 200, confirmFar: yes), 'Сначала закончите начатый визит');

    expect(await book.finishNoOrder('  ', data.settings), 'Укажите, почему без заказа');
    expect(await book.finishNoOrder('Нет денег', data.settings), isNull);
    await settle();

    expect(book.current, isNull);
    final sent = server.visits[v.uuid]!;
    expect(sent['outletId'], 1);
    expect(sent['routeId'], 1);
    expect(sent['result'], 'NO_ORDER');
    expect(sent['refuseReason'], 'Нет денег');
    expect(sent['startedAt'], '2026-10-28T10:05:00');
    expect(store.visits[v.uuid]!.sent, isTrue);
    expect(book.lastAt(1)!.sent, isTrue); // на экране — уже не «ждёт отправки»
    expect(outbox.unsent, 0);
  });

  test('далеко от магазина — только подтвердив; у магазина без точки — где агент', () async {
    gps.here = Fix(at: now, lat: 42.31, lng: 69.6, accuracy: 30); // 1,1 км
    expect(await book.start(outlet(1), radius: 200, confirmFar: no), isNull);
    expect(book.current, isNull);
    expect(asked, [1112]);
    expect(await book.start(outlet(1), radius: 200, confirmFar: yes), isNull);
    expect(book.current!.distance, 1112);
    await book.cancel();

    asked.clear();
    gps.here = Fix(at: now, lat: 42.3021, lng: 69.6, accuracy: 40); // 234 м, но точность 40 м — в пользу агента
    expect(await book.start(outlet(1), radius: 200, confirmFar: no), isNull);
    expect(book.current, isNotNull);
    expect(asked, isEmpty);
    await book.cancel();

    gps.here = null;
    expect(await book.start(outlet(1), radius: 200, confirmFar: yes), startsWith('Не удалось определить, где вы'));

    gps.here = Fix(at: now, lat: 43.2, lng: 76.9);
    final far = Outlet.fromJson({...sampleAgentData()['outlets'][0] as Map<String, dynamic>, 'lat': null, 'lng': null});
    expect(await book.start(far, radius: 200, confirmFar: yes), isNull);
    expect(book.current!.distance, isNull);
    expect(book.current!.lat, 43.2);
  });

  test('фото полки: обязательно по настройке, переснятое заменяет прежнее, уходит после визита', () async {
    final strict = AgentData.fromJson(sampleAgentData(now: now)
      ..['settings'] = {...sampleAgentData()['settings'] as Map<String, dynamic>, 'shelfPhotoRequired': true});
    await book.start(outlet(1), radius: 200, confirmFar: yes);
    expect(await book.finishNoOrder('Нет денег', strict.settings), 'Сначала сфотографируйте полку');

    await book.takePhoto();
    final first = book.current!.photo!;
    await book.takePhoto();
    final second = book.current!.photo!;
    expect(second, isNot(first));
    expect(File(first).existsSync(), isFalse);

    final uuid = book.current!.uuid;
    expect(await book.finishNoOrder('Нет денег', strict.settings), isNull);
    await settle();
    expect(server.photos[uuid], FakeCamera.jpeg);
    expect(store.visits[uuid]!.photoSent, isTrue);
  });

  test('без сети визит и фото ждут на телефоне, потом уходят', () async {
    server.offline = true;
    await book.start(outlet(1), radius: 200, confirmFar: yes);
    await book.takePhoto();
    final uuid = book.current!.uuid;
    await book.finishNoOrder('Магазин закрыт', data.settings);
    await settle();
    expect(outbox.unsent, 2); // визит и фото

    server.offline = false;
    await outbox.flush();
    expect(outbox.unsent, 0);
    expect(server.visits.keys, [uuid]);
    expect(server.photos.keys, [uuid]);
  });

  test('сервер не принял визит — помечен и больше не отправляется', () async {
    server.rejectVisits = 'Магазин не найден — обновите данные на телефоне';
    await book.start(outlet(1), radius: 200, confirmFar: yes);
    final uuid = book.current!.uuid;
    await book.finishNoOrder('Нет денег', data.settings);
    await settle();

    expect(store.visits[uuid]!.error, 'Магазин не найден — обновите данные на телефоне');
    expect(outbox.unsent, 0);
    final before = server.count('/api/mobile/agent/visits');
    await outbox.flush();
    expect(server.count('/api/mobile/agent/visits'), before);
  });

  test('отменённый визит стирается и не уходит', () async {
    await book.start(outlet(1), radius: 200, confirmFar: yes);
    await book.takePhoto();
    final photo = book.current!.photo!;
    await book.cancel();

    expect(book.current, isNull);
    expect(store.visits, isEmpty);
    expect(File(photo).existsSync(), isFalse);
    await outbox.flush();
    expect(server.visits, isEmpty);
  });

  test('визиты с сервера вместе с телефонными, без повторов; после перезапуска — с телефона', () async {
    await book.start(outlet(1), radius: 200, confirmFar: yes);
    final mine = book.current!.uuid;
    await book.finishNoOrder('Нет денег', data.settings);
    final json = sampleAgentData(now: now)
      ..['visits'] = [
        {'uuid': mine, 'outletId': 1, 'startedAt': '2026-10-28T10:05:00', 'result': 'NO_ORDER', 'refuseReason': 'Нет денег', 'photo': false},
        {'uuid': 'v-2', 'outletId': 2, 'startedAt': '2026-10-28T09:30:00', 'finishedAt': '2026-10-28T09:40:00', 'result': 'ORDER', 'photo': true},
        {'uuid': 'v-old', 'outletId': 2, 'startedAt': '2026-10-27T09:30:00', 'result': 'ORDER', 'photo': false},
      ];
    book.serverVisits(AgentData.fromJson(json));

    expect(book.today.map((v) => v.uuid), ['v-2', mine]);
    expect(book.lastAt(2)!.withPhoto, isTrue);

    final again = VisitBook(store: store, outbox: outbox, location: gps, camera: camera, clock: () => now);
    await again.load();
    expect(again.lastAt(1)!.reason, 'Нет денег');
  });

  test('заказ с возвратом заканчивает визит: визит и заказ уходят, номер и статус с сервера, черновик стёрт', () async {
    server.needsApproval = true;
    await book.start(outlet(1), routeId: 1, radius: 200, confirmFar: yes);
    final visit = book.current!.uuid;
    await book.saveDraft({1: 3}, const [ReturnItem(productId: 2, qty: 4, reason: 'PACKAGING')]);
    final draft = await book.draft();
    expect(draft.items, {1: 3});
    expect([draft.returns.single.qty, draft.returns.single.reason], [4, 'PACKAGING']);

    expect(
        await book.finishWithOrder(
            items: {1: 12, 2: 20},
            total: 12000,
            returns: const [ReturnItem(productId: 2, qty: 4, reason: 'PACKAGING')],
            returnTotal: 1200,
            payment: 'CREDIT',
            deliveryDate: DateTime(2026, 10, 29, 15),
            comment: '  после обеда ',
            settings: data.settings),
        isNull);
    await settle();

    expect(book.current, isNull);
    expect(book.lastAt(1)!.result, 'ORDER');
    final sent = server.orders.values.single;
    expect(sent['visitUuid'], visit);
    expect(sent['deliveryDate'], '2026-10-29');
    expect(sent['payment'], 'CREDIT');
    expect(sent['comment'], 'после обеда');
    expect(sent['items'], [{'productId': 1, 'qty': 12}, {'productId': 2, 'qty': 20}]);
    expect(sent['returns'], [{'productId': 2, 'qty': 4, 'reason': 'PACKAGING'}]);
    expect(server.visits[visit]!['result'], 'ORDER');

    final o = book.ordersAt(1).single;
    expect(o.number, 'З-281026-1');
    expect(o.status, 'NEEDS_APPROVAL');
    expect(o.note, 'Долг сверх лимита — ждёт разрешения оператора');
    expect(o.total, 16000); // итог сервера
    expect(o.returnTotal, 2000);
    expect(book.orderOf(book.lastAt(1)!)?.uuid, o.uuid);
    expect(book.todayOrders.single.uuid, o.uuid);
    expect((await book.draft()).items, isEmpty);
    expect(store.data, isNot(contains(VisitBook.draftKey)));
    expect(outbox.unsent, 0);
  });

  test('заказ без сети ждёт; статус с сервера (отменили) виден у заказа с телефона', () async {
    server.offline = true;
    await book.start(outlet(2), radius: 200, confirmFar: yes);
    await book.finishWithOrder(
        items: {2: 5}, total: 1500, payment: 'CASH', deliveryDate: DateTime(2026, 10, 29), settings: data.settings);
    await settle();
    expect(outbox.unsent, 2); // визит и заказ
    expect(book.ordersAt(2).single.sent, isFalse);

    server.offline = false;
    await outbox.flush();
    await settle();
    final uuid = book.ordersAt(2).single.uuid;
    expect(book.ordersAt(2).single.number, 'З-281026-1');

    final json = sampleAgentData(now: now)
      ..['orders'] = [
        {'uuid': uuid, 'outletId': 2, 'number': 'З-281026-1', 'createdAt': '2026-10-28T10:05:00',
          'deliveryDate': '2026-10-29', 'payment': 'CASH', 'status': 'CANCELLED', 'statusLabel': 'Отменён',
          'note': 'Отменил: магазин закрыт', 'total': 1500, 'lines': []},
      ];
    book.serverVisits(AgentData.fromJson(json));
    expect(book.ordersAt(2).single.statusLabel, 'Отменён');
    expect(book.ordersAt(2).single.note, 'Отменил: магазин закрыт');
  });

  test('черновик другого визита не подставляется; отмена визита стирает черновик', () async {
    await store.write(VisitBook.draftKey, {'visit': 'другой', 'items': '{"1":4}'});
    await book.start(outlet(1), radius: 200, confirmFar: yes);
    expect((await book.draft()).items, isEmpty);
    // черновик прежней версии — без возврата
    await store.write(VisitBook.draftKey, {'visit': book.current!.uuid, 'items': '{"1":4}'});
    expect([(await book.draft()).items, (await book.draft()).returns], [{1: 4}, isEmpty]);
    await book.saveDraft({2: 1});
    await book.cancel();
    expect(store.data, isNot(contains(VisitBook.draftKey)));
  });
}

