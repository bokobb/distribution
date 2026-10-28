import 'package:distribution_mobile/data/agent_data.dart';
import 'package:distribution_mobile/data/local_store.dart';
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
    expect(data.products.single.priceFor('RETAIL'), 600);
    expect(data.products.single.priceFor('WHOLESALE'), 500);
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
}
