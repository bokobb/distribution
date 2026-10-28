import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/format.dart';
import 'package:distribution_mobile/main.dart';
import 'package:distribution_mobile/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_camera.dart';
import 'fake_location.dart';
import 'fake_server.dart';
import 'memory_store.dart';

Future<void> logIn(WidgetTester t, {String password = 'пароль'}) async {
  await t.enterText(find.widgetWithText(TextFormField, 'Телефон или логин'), '87010000101');
  await t.enterText(find.widgetWithText(TextFormField, 'Пароль'), password);
  await t.tap(find.text('Войти'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('пустые поля: подсказки, на сервер не идём', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));

    await t.tap(find.text('Войти'));
    await t.pump();

    expect(find.text('Введите телефон или логин'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  testWidgets('агент входит — «Мой день», ключ устройства сохранён', (t) async {
    final store = SessionStore();
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: FakeServer().client), store: store));

    await logIn(t);

    expect(find.text('Мой день'), findsOneWidget);
    expect(find.text('Иван · Своя доставка'), findsOneWidget);
    expect((await store.load())?.name, 'Иван');
    expect(await store.deviceToken(), 'ключ');
  });

  testWidgets('экспедитор входит — «Рейс»', (t) async {
    final api = ApiClient(baseUrl: 'http://s', client: FakeServer(role: 'EXPEDITOR').client);
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: api, store: SessionStore()));

    await logIn(t);

    expect(find.text('Рейс'), findsOneWidget);
  });

  testWidgets('отказ сервера показывается, вход не запоминается', (t) async {
    final store = SessionStore();
    final api = ApiClient(baseUrl: 'http://s', client: FakeServer(role: 'OPERATOR').client);
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: api, store: store));

    await logIn(t);

    expect(find.text('Оператор работает в веб-админке.'), findsOneWidget);
    expect(await store.load(), isNull);
  });

  testWidgets('временный пароль — сначала свой, потом «Мой день»', (t) async {
    final server = FakeServer(mustChange: true);
    final store = SessionStore();
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: store));

    await logIn(t);
    expect(find.text('Иван, придумайте свой пароль'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Временный пароль'), 'пароль');
    await t.enterText(find.widgetWithText(TextFormField, 'Новый пароль'), 'свой-пароль-1');
    await t.enterText(find.widgetWithText(TextFormField, 'Повторите новый пароль'), 'свой-пароль-2');
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(find.text('Пароли не совпадают'), findsOneWidget);
    expect(server.count('/api/mobile/auth/password'), 0);

    await t.enterText(find.widgetWithText(TextFormField, 'Повторите новый пароль'), 'свой-пароль-1');
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();

    expect(find.text('Мой день'), findsOneWidget);
    expect((await store.load())?.mustChangePassword, isFalse);
  });

  testWidgets('вход на телефоне закрыт — при запуске снова вход с подсказкой', (t) async {
    final server = FakeServer()..keyOpen = false;
    final store = SessionStore();
    const s = Session(userId: 1, name: 'Иван', role: 'AGENT');
    await store.save(s);
    await store.saveDeviceToken('ключ');
    final api = ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ');

    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: api, store: store, session: s));
    await t.pumpAndSettle();

    expect(find.text('Вход на этом телефоне закрыт — войдите с паролем'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    expect(await store.load(), isNull);
    expect(await store.deviceToken(), isNull);
  });

  testWidgets('без сети при запуске — работаем с тем, что на телефоне', (t) async {
    final server = FakeServer()..offline = true;
    const s = Session(userId: 1, name: 'Иван', role: 'AGENT', company: 'Своя доставка');
    final api = ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ');

    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: api, store: SessionStore(), session: s));
    await t.pumpAndSettle();

    expect(find.text('Мой день'), findsOneWidget);
  });

  testWidgets('выход закрывает ключ на сервере и возвращает на вход', (t) async {
    final server = FakeServer();
    final store = SessionStore();
    const s = Session(userId: 1, name: 'Иван', role: 'AGENT');
    await store.save(s);
    await store.saveDeviceToken('ключ');
    final api = ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ');
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: api, store: store, session: s));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Меню'));
    await t.pumpAndSettle();
    await t.tap(find.text('Выйти'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Выйти'));
    await t.pumpAndSettle();

    expect(find.text('Войти'), findsOneWidget);
    expect(server.count('/api/mobile/auth/logout'), 1);
    expect(await store.load(), isNull);
    expect(await store.deviceToken(), isNull);
  });

  testWidgets('«Мой день»: маршрут сегодня, магазины по порядку, долг и просрочка', (t) async {
    final local = MemoryStore();
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: local, api: ApiClient(baseUrl: 'http://s', client: FakeServer().client), store: SessionStore()));

    await logIn(t);

    expect(find.textContaining('Центр · Шымкент · 2 магазина'), findsOneWidget);
    expect(find.text('Магазин «Сайрам»'), findsNothing);
    final first = t.getTopLeft(find.text('Магазин «Береке»')).dy;
    final second = t.getTopLeft(find.text('Магазин «Арай»')).dy;
    expect(first, lessThan(second));
    expect(find.text('долг 45\u00a0000\u00a0₸'), findsOneWidget);
    expect(find.text('просрочено 12\u00a0000\u00a0₸'), findsOneWidget);
    expect(find.text('Обновлено сегодня в 09:15'), findsOneWidget);
    expect(local.data['agent'], isNotNull);

    // другой день недели — другой маршрут
    final tomorrow = DateTime.now().weekday % 7 + 1;
    await t.tap(find.text(['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][tomorrow - 1]));
    await t.pumpAndSettle();
    expect(find.text('Магазин «Сайрам»'), findsOneWidget);
    expect(find.text('Магазин «Арай»'), findsNothing);
  });

  testWidgets('без сети — маршрут с телефона и подсказка, когда обновляли', (t) async {
    final server = FakeServer()..offline = true;
    final local = MemoryStore()..data['agent'] = sampleAgentData();
    const s = Session(userId: 1, name: 'Иван', role: 'AGENT');
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: local, api: ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ'), store: SessionStore(), session: s));
    await t.pumpAndSettle();

    expect(find.text('Магазин «Арай»'), findsOneWidget);
    expect(find.text('Нет связи с сервером. Данные сегодня в 09:15'), findsOneWidget);
  });

  testWidgets('карточка магазина: долг, лимит, прайс, адрес', (t) async {
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: FakeServer().client), store: SessionStore()));
    await logIn(t);

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();

    expect(find.text('45\u00a0000\u00a0₸'), findsOneWidget);
    expect(find.text('Просрочено'), findsOneWidget);
    expect(find.text('100\u00a0000\u00a0₸'), findsOneWidget);
    expect(find.text('7 дней'), findsOneWidget);
    expect(find.text('Опт'), findsOneWidget);
    expect(find.text('ул. Байтурсынова, 1'), findsOneWidget);
  });

  testWidgets('выход стирает данные с телефона', (t) async {
    final local = MemoryStore()..data['agent'] = sampleAgentData();
    const s = Session(userId: 1, name: 'Иван', role: 'AGENT');
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: local, api: ApiClient(baseUrl: 'http://s', client: FakeServer().client, deviceToken: 'ключ'), store: SessionStore(), session: s));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Меню'));
    await t.pumpAndSettle();
    await t.tap(find.text('Выйти'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Выйти'));
    await t.pumpAndSettle();

    expect(local.data, isEmpty);
  });

  testWidgets('«Начать день» и выход: день закрывается, журнал уходит на сервер', (t) async {
    final server = FakeServer();
    final local = MemoryStore();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: local, api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    expect(find.text('Рабочий день не начат'), findsOneWidget);

    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();
    expect(find.textContaining('Рабочий день с '), findsOneWidget);
    expect(find.text('GPS ещё не отметился'), findsOneWidget);

    await t.tap(find.byTooltip('Меню'));
    await t.pumpAndSettle();
    await t.tap(find.text('Выйти'));
    await t.pumpAndSettle();
    expect(find.textContaining('Рабочий день будет закончен.'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Выйти'));
    await t.pumpAndSettle();
    // закрытие дня ждёт отписки от потоков GPS — даём отработать настоящему циклу событий
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    expect(find.text('Войти'), findsOneWidget);
    expect(server.trackEvents.map((e) => e['kind']), containsAllInOrder(['DAY_START', 'DAY_END']));
  });

  testWidgets('нет доступа к местоположению — подсказка, день не начат', (t) async {
    final gps = FakeLocation()..problem = 'Разрешите приложению доступ к местоположению в настройках телефона';
    await t.pumpWidget(DistributionApp(
        location: gps, camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: FakeServer().client), store: SessionStore()));
    await logIn(t);

    await t.tap(find.text('Начать день'));
    await t.pump();

    expect(find.text('Разрешите приложению доступ к местоположению в настройках телефона'), findsOneWidget);
    expect(find.text('Рабочий день не начат'), findsOneWidget);
  });

  testWidgets('визит: начать день, магазин, «Начать визит», «Без заказа» с причиной — на сервер', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    await t.tap(find.text('Начать визит'));
    await t.pump();
    expect(find.text('Сначала начните рабочий день на главном экране'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    await t.tap(find.text('Начать визит'));
    await t.pumpAndSettle();
    expect(find.textContaining('Визит с '), findsOneWidget);
    expect(find.text('0 м от магазина'), findsOneWidget);

    await t.tap(find.text('Без заказа'));
    await t.pumpAndSettle();
    await t.tap(find.text('Хозяина нет на месте'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    expect(find.textContaining('Сегодня был в '), findsOneWidget);
    expect(find.text('Начать визит ещё раз'), findsOneWidget);
    expect(find.text('Ждёт отправки'), findsNothing);
    expect(server.visits.values.single['refuseReason'], 'Хозяина нет на месте');

    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.textContaining('без заказа: Хозяина нет на месте'), findsOneWidget);
  });

  testWidgets('заказ: товары, количество, оформление в долг сверх лимита — на сервер с визитом', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();
    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    await t.tap(find.text('Начать визит'));
    await t.pumpAndSettle();

    await t.tap(find.text('Заказ'));
    await t.pumpAndSettle();
    expect(find.text('нет цены'), findsOneWidget); // торт без цены не добавить
    await t.tap(find.byTooltip('Добавить Печенье овсяное'));
    await t.pump();
    await t.tap(find.byTooltip('Больше'));
    await t.pump();
    await t.tap(find.text('2'));
    await t.pumpAndSettle();
    await t.tap(find.text('+ коробка (12 шт)'));
    await t.pump();
    await t.tap(find.text('Готово'));
    await t.pumpAndSettle();
    expect(find.text('= ${money(7000)}'), findsOneWidget); // 14 × 500

    await t.enterText(find.widgetWithText(TextField, 'Поиск товара'), '4870001');
    await t.pump();
    expect(find.text('Печенье овсяное'), findsNothing);
    await t.tap(find.byTooltip('Добавить Вафли сливочные'));
    await t.pump();
    expect(find.text(money(7300)), findsOneWidget);

    await t.tap(find.text('Оформить'));
    await t.pumpAndSettle();
    await t.tap(find.text('В долг'));
    await t.pump();
    // долг 45 000 + 7 300 при лимите 100 000 — в пределах
    expect(find.textContaining('больше лимита'), findsNothing);
    await t.tap(find.text('Сохранить заказ'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    expect(find.textContaining('Сегодня был в '), findsOneWidget);
    expect(find.textContaining('Заказ З-281026-1 на ${money(7500)} · В долг'), findsOneWidget); // итог сервера: 15 шт × 500
    final sent = server.orders.values.single;
    expect(sent['items'], [{'productId': 1, 'qty': 14}, {'productId': 2, 'qty': 1}]);
    expect(sent['visitUuid'], server.visits.keys.single);
  });
}

