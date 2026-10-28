import 'package:distribution_mobile/data/expeditor_data.dart';
import 'package:distribution_mobile/data/expeditor_repo.dart';
import 'package:distribution_mobile/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';
import 'memory_store.dart';

void main() {
  test('рейс сегодня и на завтра, точки по порядку, что выдано', () {
    final data = ExpeditorData.fromJson(sampleExpeditorData(now: DateTime(2026, 10, 28)));

    expect(data.companyName, 'Своя доставка');
    expect(data.settings.acceptKaspi, isTrue);
    expect(data.current.map((t) => t.number), ['Р-281026-1']);
    expect(data.upcoming.map((t) => t.number), ['Р-291026-1']);
    final trip = data.current.single;
    expect(trip.stops.map((s) => s.outlet.name), ['Магазин «Арай»', 'Магазин «Береке»']);
    expect(trip.done, 1);
    final first = trip.stops.first.order;
    expect([first.total, first.paymentLabel, first.done, first.comment], [13500, 'Наличные', false, 'после обеда']);
    expect(first.lines.first.sum, 12000);
    expect(first.lines.first.delivered, isNull);
    expect(trip.stops.last.order.lines.single.delivered, 10);
    expect(trip.stops.first.outlet.overdue, 12000);
  });

  test('с сервера на телефон; без сети — то, что на телефоне', () async {
    final server = FakeServer(role: 'EXPEDITOR');
    final api = ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ');
    final repo = ExpeditorRepo(api, MemoryStore());
    expect(await repo.local(), isNull);

    await api.refresh();
    final pulled = await repo.pull();
    expect(pulled.trips, hasLength(2));

    server.offline = true;
    await expectLater(repo.pull(), throwsA(isA<ApiException>()));
    expect((await repo.local())!.trips.first.number, 'Р-281026-1');
  });
}
