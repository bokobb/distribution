import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/data/expeditor_data.dart';
import 'package:distribution_mobile/day_summary.dart';
import 'package:distribution_mobile/deliveries.dart';
import 'package:distribution_mobile/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_camera.dart';
import 'fake_location.dart';
import 'fake_server.dart';
import 'memory_store.dart';

void main() {
  late FakeServer server;
  late Outbox outbox;
  late DeliveryBook book;
  final now = DateTime(2026, 10, 28, 11, 20);

  setUp(() {
    server = FakeServer(role: 'EXPEDITOR')..expeditorData = sampleExpeditorData(now: now);
    final store = MemoryStore();
    outbox = Outbox(
        api: ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ'), store: store, clock: () => now);
    book = DeliveryBook(store: store, outbox: outbox, location: FakeLocation(), camera: FakeCamera(), clock: () => now);
  });

  tearDown(() {
    book.dispose();
    outbox.dispose();
  });

  ExpeditorData data() => ExpeditorData.fromJson(server.expeditorData);
  TripSummary summary(ExpeditorData d) => TripSummary.of(d.current.single, book, d.syncedAt);
  List<Object> money(TripSummary s) =>
      [s.deliveredTotal, s.cash, s.kaspi, s.oldDebt, s.debt, s.returnsQty, s.returnsTotal, s.backQty];

  test('по данным сервера: «Береке» выдан в долг, «Арай» не пройден — весь его товар в машине', () {
    final s = summary(data());
    expect([s.full, s.partial, s.refused, s.left, s.done, s.unsent], [1, 0, 0, 1, 1, 0]);
    expect(money(s), [5000, 0, 0, 0, 5000, 0, 0, 29]);
  });

  test('что на телефоне — учтено; ушло на сервер и данные обновились — не задваивается', () async {
    final before = data();
    final trip = before.current.single;
    server.offline = true;
    await book.deliver(trip, trip.stops.first, items: {1: 22, 2: 5}, cash: 10000, settings: before.settings);
    await book.payDebt(trip, trip.stops.last, kaspi: 3000, settings: before.settings);
    await book.returnGoods(trip, trip.stops.last, items: {1: 2}, reason: 'DEFECT', total: 1000);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    var s = summary(before);
    expect([s.full, s.partial, s.left, s.unsent], [1, 1, 0, 3]);
    // выдано 5 000 + 12 500; в долг 5 000 («Береке») + 2 500 недоплаты «Арай»; в машине 2 печенья
    const expected = [17500, 10000, 3000, 3000, 7500, 2, 1000, 2];
    expect(money(s), expected);

    server.offline = false;
    await outbox.flush();
    await book.load();
    s = summary(before); // ушло, а данные ещё старые
    expect([money(s), s.unsent], [expected, 0]);

    server.expeditorData['syncedAt'] = '2026-10-28T12:00:00';
    s = summary(data()); // свежие данные: всё уже на сервере
    expect([s.full, s.partial, s.unsent], [1, 1, 0]);
    expect(money(s), expected);
  });
}
