import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/data/track.dart';
import 'package:distribution_mobile/outbox.dart';
import 'package:distribution_mobile/workday.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_location.dart';
import 'fake_server.dart';
import 'memory_store.dart';

void main() {
  late FakeServer server;
  late MemoryStore store;
  late FakeLocation gps;
  late DateTime now;

  Workday workday({DateTime Function()? clock}) => Workday(
        outbox: Outbox(
            api: ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ', appVersion: '1.0.0+1'),
            store: store),
        store: store,
        location: gps,
        clock: clock ?? () => now,
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

  group('рабочее время', () {
    /// Записи журнала: «DAY_START 08:40 сам…».
    List<String> journal() => [
          for (final e in store.events)
            [e.kind, '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}', ?e.note]
                .join(' ')
        ];

    /// Часы, которые двигает тест: с start. Заглушки — внутри, иначе их Future не завершаются в поддельном времени.
    void clocked(DateTime start, void Function(FakeAsync fa, Workday w) body) => fakeAsync((fa) {
          server = FakeServer();
          store = MemoryStore();
          gps = FakeLocation();
          final w = workday(clock: () => start.add(fa.elapsed));
          body(fa, w);
          w.dispose();
        });

    test('открыл приложение в рабочее время — день начался сам, без кнопки', () async {
      final w = workday();
      await w.restore();
      w.setHours('08:00', '20:00');
      expect(w.open, isFalse, reason: 'приложение ещё не открыто (под замком)');

      w.opened();
      await settle();

      expect(w.open, isTrue);
      expect(w.hours, 'с 08:00 до 20:00');
      expect(gps.asked, 0, reason: 'разрешение не спрашивается — уже дано');
      expect(gps.tracking, 1);
      expect(journal(), ['APP_OPEN 08:40', 'DAY_START 08:40 ${Workday.auto}']);
    });

    test('рабочее время пришло позже, чем открыли приложение (первая загрузка данных)', () async {
      final w = workday();
      await w.restore();
      w.opened();
      await settle();
      expect(w.open, isFalse);

      w.setHours('08:00:00', '20:00:00');
      await settle();
      expect(w.open, isTrue);
    });

    test('до начала рабочего времени — ждёт и начинается сам в 08:00, если приложение открыто', () {
      clocked(DateTime(2026, 10, 28, 7, 50), (fa, w) {
        w.restore();
        w.setHours('08:00', '20:00');
        w.opened();
        fa.flushMicrotasks();
        expect(w.open, isFalse);

        fa.elapse(const Duration(minutes: 10));
        expect(w.open, isTrue);
        expect(w.startedAt, DateTime(2026, 10, 28, 8));
      });
    });

    test('в конце рабочего времени день закрывается сам', () {
      clocked(DateTime(2026, 10, 28, 19, 50), (fa, w) {
        w.restore();
        w.setHours('08:00', '20:00');
        w.opened();
        fa.flushMicrotasks();
        expect(w.open, isTrue);

        w.away(); // свернули — закрыться всё равно должен
        fa.elapse(const Duration(minutes: 10));

        expect(w.open, isFalse);
        expect(w.endedAt, DateTime(2026, 10, 28, 20));
        expect(journal().last, 'DAY_END 20:00 ${Workday.auto}');

        gps.fix(DateTime(2026, 10, 28, 20, 5));
        fa.flushMicrotasks();
        expect(store.points, isEmpty, reason: 'GPS после конца дня не пишется');
      });
    });

    test('телефон проспал конец рабочего времени — день закрыт временем конца, точка после него не пишется', () async {
      final w = workday();
      await w.restore();
      w.setHours('08:00', '20:00');
      w.opened();
      await settle();

      now = DateTime(2026, 10, 28, 20, 7);
      gps.fix(now);
      await settle();

      expect(w.open, isFalse);
      expect(w.endedAt, DateTime(2026, 10, 28, 20));
      expect(store.points, isEmpty);
    });

    test('день открыт с утра, приложение запустили вечером — закрыт временем конца', () async {
      await store.addEvent(TrackEvent(uuid: 'a', at: DateTime(2026, 10, 28, 8, 30), kind: 'DAY_START'));
      now = DateTime(2026, 10, 28, 21);
      final w = workday();
      await w.restore();
      expect(w.open, isTrue);

      w.setHours('08:00', '20:00');
      await settle();

      expect(w.open, isFalse);
      expect(w.endedAt, DateTime(2026, 10, 28, 20));
      expect(journal().last, 'DAY_END 20:00 ${Workday.auto}');
    });

    test('закончил день сам — при следующем открытии день снова не начинается', () async {
      final w = workday();
      await w.restore();
      w.setHours('08:00', '20:00');
      w.opened();
      await settle();
      now = DateTime(2026, 10, 28, 13);
      await w.end();

      w.away();
      w.opened();
      await settle();

      expect(w.open, isFalse);
      expect(w.endedAt, DateTime(2026, 10, 28, 13));
      expect(await w.start(), isNull, reason: 'вручную начать можно');
      expect(w.open, isTrue);
    });

    test('начал вручную после рабочего времени — сам не закрывается', () {
      clocked(DateTime(2026, 10, 28, 20, 30), (fa, w) {
        w.restore();
        w.setHours('08:00', '20:00');
        w.opened();
        fa.flushMicrotasks();
        expect(w.open, isFalse, reason: 'после рабочего времени сам не начинается');

        w.start();
        fa.flushMicrotasks();
        fa.elapse(const Duration(hours: 2));
        expect(w.open, isTrue);
      });
    });

    test('нет разрешения на местоположение — сам не начинается и не спрашивает, на главной подсказка', () async {
      gps.problem = 'Разрешите доступ';
      final w = workday();
      await w.restore();
      w.setHours('08:00', '20:00');
      w.opened();
      await settle();

      expect(w.open, isFalse);
      expect(w.noAccess, isTrue);
      expect(gps.asked, 0);

      gps.problem = null; // разрешил в настройках телефона и вернулся
      w.away();
      w.opened();
      await settle();
      expect(w.open, isTrue);
      expect(w.noAccess, isFalse);
    });

    test('GPS на телефоне выключен — день всё равно начинается, а выключенный GPS видно', () async {
      gps.on = false;
      final w = workday();
      await w.restore();
      w.setHours('08:00', '20:00');
      w.opened();
      await settle();

      expect(w.open, isTrue);
      expect(w.gpsOff, isTrue);
      expect(store.kinds(), ['APP_OPEN', 'DAY_START', 'GPS_OFF']);
    });

    test('без рабочего времени (старые настройки) — только кнопкой', () async {
      final w = workday();
      await w.restore();
      w.setHours(null, null);
      w.opened();
      await settle();
      expect(w.open, isFalse);
      expect(w.hours, isNull);
    });
  });
}
