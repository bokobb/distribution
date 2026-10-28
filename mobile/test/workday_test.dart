import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/data/track.dart';
import 'package:distribution_mobile/outbox.dart';
import 'package:distribution_mobile/workday.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_location.dart';
import 'fake_server.dart';
import 'memory_store.dart';

void main() {
  late FakeServer server;
  late MemoryStore store;
  late FakeLocation gps;
  late DateTime now;

  Workday workday() => Workday(
        outbox: Outbox(
            api: ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ', appVersion: '1.0.0+1'),
            store: store),
        store: store,
        location: gps,
        clock: () => now,
      );

  /// Дать потокам и отправке отработать.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  setUp(() {
    server = FakeServer();
    store = MemoryStore();
    gps = FakeLocation();
    now = DateTime(2026, 10, 28, 8, 40);
  });

  test('начал день — точки раз в интервал уходят на сервер вместе с журналом', () async {
    final w = workday();
    await w.restore();

    expect(await w.start(), isNull);
    expect(w.open, isTrue);
    expect(w.startedAt, now);
    expect(gps.interval, const Duration(minutes: 5));

    gps.fix(DateTime(2026, 10, 28, 8, 41));
    gps.fix(DateTime(2026, 10, 28, 8, 42)); // чаще интервала — не сохраняется
    gps.fix(DateTime(2026, 10, 28, 8, 46));
    await settle();

    expect(store.points.map((p) => p.at.minute), [41, 46]);
    expect(store.points.first.battery, 77);
    expect(server.trackEvents.map((e) => e['kind']), ['APP_OPEN', 'DAY_START']);
    expect(server.trackEvents.first['appVersion'], '1.0.0+1');
    expect(server.trackPoints, hasLength(2));
    expect(server.lastUnsent, 0);
    expect(w.unsent, 0);
    expect(w.lastFix, DateTime(2026, 10, 28, 8, 46));
  });

  test('без доступа к местоположению день не начинается', () async {
    gps.problem = 'Разрешите доступ';
    final w = workday();

    expect(await w.start(), 'Разрешите доступ');
    expect(w.open, isFalse);
    expect(store.kinds(), isNot(contains('DAY_START')));
    expect(gps.tracking, 0);
  });

  test('без сети всё копится на телефоне и уходит, когда сеть появилась', () async {
    server.offline = true;
    final w = workday();
    await w.start();
    gps.fix(DateTime(2026, 10, 28, 8, 41));
    await settle();

    expect(w.unsent, 2);
    expect(server.trackEvents, isEmpty);

    server.offline = false;
    await w.flush();
    expect(w.unsent, 0);
    expect(server.trackEvents.map((e) => e['kind']), ['DAY_START']);
    expect(server.trackPoints, hasLength(1));
  });

  test('GPS выключили и включили — в журнал', () async {
    final w = workday();
    await w.start();

    gps.status.add(false);
    await settle();
    expect(w.gpsOff, isTrue);
    gps.status.add(true);
    await settle();

    expect(w.gpsOff, isFalse);
    expect(store.kinds(), ['DAY_START', 'GPS_OFF', 'GPS_ON']);
  });

  test('закончил день — GPS остановлен, точки больше не пишутся', () async {
    final w = workday();
    await w.start();
    now = DateTime(2026, 10, 28, 18, 10);

    await w.end();
    gps.fix(DateTime(2026, 10, 28, 18, 20));
    await settle();

    expect(w.open, isFalse);
    expect(w.endedAt, now);
    expect(store.kinds(), ['DAY_START', 'DAY_END']);
    expect(store.points, isEmpty);
  });

  test('перезапуск приложения: открытый сегодня день продолжается, вчерашний — нет', () async {
    await store.addEvent(TrackEvent(uuid: 'a', at: DateTime(2026, 10, 27, 9), kind: 'DAY_START'));
    var w = workday();
    await w.restore();
    expect(w.open, isFalse);
    expect(gps.tracking, 0);

    await store.addEvent(TrackEvent(uuid: 'b', at: DateTime(2026, 10, 28, 8, 30), kind: 'DAY_START'));
    w = workday();
    await w.restore();
    expect(w.open, isTrue);
    expect(w.startedAt, DateTime(2026, 10, 28, 8, 30));
    expect(gps.tracking, 1);

    await store.addEvent(TrackEvent(uuid: 'c', at: DateTime(2026, 10, 28, 8, 35), kind: 'DAY_END'));
    w = workday();
    await w.restore();
    expect(w.open, isFalse);
    expect(w.endedAt, DateTime(2026, 10, 28, 8, 35));
  });

  test('интервал из настроек компании перезапускает GPS', () async {
    final w = workday();
    await w.start();

    w.setInterval(const Duration(minutes: 10));

    expect(gps.interval, const Duration(minutes: 10));
    expect(gps.tracking, 2);
  });
}
