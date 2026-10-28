import 'dart:io';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/data/agent_data.dart';
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

  setUp(() async {
    server = FakeServer();
    store = MemoryStore();
    gps = FakeLocation();
    camera = FakeCamera();
    outbox = Outbox(api: ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ'), store: store);
    book = VisitBook(store: store, outbox: outbox, location: gps, camera: camera, clock: () => now);
    data = AgentData.fromJson(sampleAgentData(now: now));
  });

  tearDown(() => camera.clear());

  Outlet outlet(int id) => data.outlets[id]!;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('рядом с магазином: визит идёт; без заказа — с причиной, уходит на сервер', () async {
    gps.here = Fix(at: now, lat: 42.3009, lng: 69.6, accuracy: 15); // 100 м
    expect(await book.start(outlet(1), routeId: 1, radius: 200), isNull);
    final v = book.current!;
    expect(v.distance, 100);
    expect(book.lastAt(1), same(v));
    expect(await book.start(outlet(2), radius: 200), 'Сначала закончите начатый визит');

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

  test('далеко от магазина — визит не начинается; у магазина без точки — где агент', () async {
    gps.here = Fix(at: now, lat: 42.31, lng: 69.6, accuracy: 30); // 1,1 км
    expect(await book.start(outlet(1), radius: 200), startsWith('Вы в 1,1 км от магазина'));
    expect(book.current, isNull);

    gps.here = Fix(at: now, lat: 42.3021, lng: 69.6, accuracy: 40); // 234 м, но точность 40 м — в пользу агента
    expect(await book.start(outlet(1), radius: 200), isNull);
    await book.cancel();

    gps.here = null;
    expect(await book.start(outlet(1), radius: 200), startsWith('Не удалось определить, где вы'));

    gps.here = Fix(at: now, lat: 43.2, lng: 76.9);
    final far = Outlet.fromJson({...sampleAgentData()['outlets'][0] as Map<String, dynamic>, 'lat': null, 'lng': null});
    expect(await book.start(far, radius: 200), isNull);
    expect(book.current!.distance, isNull);
    expect(book.current!.lat, 43.2);
  });

  test('фото полки: обязательно по настройке, переснятое заменяет прежнее, уходит после визита', () async {
    final strict = AgentData.fromJson(sampleAgentData(now: now)
      ..['settings'] = {...sampleAgentData()['settings'] as Map<String, dynamic>, 'shelfPhotoRequired': true});
    await book.start(outlet(1), radius: 200);
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
    await book.start(outlet(1), radius: 200);
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
    await book.start(outlet(1), radius: 200);
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
    await book.start(outlet(1), radius: 200);
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
    await book.start(outlet(1), radius: 200);
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
}
