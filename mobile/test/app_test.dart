import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/format.dart';
import 'package:distribution_mobile/main.dart';
import 'package:distribution_mobile/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Прокрутить к виджету и нажать. Сначала дать полю ввода прокрутить к курсору — иначе оно уведёт прокрутку обратно.
Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.pumpAndSettle();
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

/// Дать отработать настоящему вводу-выводу (файл фото): каждый его шаг ждёт кадра.
Future<void> settleIo(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
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

  testWidgets('«Отправка»: без сети ждёт, «Отправить сейчас» отправляет', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    server.offline = true;
    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Меню'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Отправка · ждут'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.text('Ждут отправки: 1'), findsOneWidget); // «начал день» — без сети
    expect(find.text('Журнал и точки GPS'), findsOneWidget);
    expect(find.text('Нет связи с сервером — приложение повторит само'), findsOneWidget);

    server.offline = false;
    await t.tap(find.text('Отправить сейчас'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.text('Всё отправлено'), findsOneWidget);
    expect(server.trackEvents.map((e) => e['kind']), containsAll(['APP_OPEN', 'DAY_START']));
  });

  testWidgets('новый магазин: форма, без сети — «ждёт отправки», после отправки — в маршруте «на проверке»', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    await t.tap(find.text('Магазин'));
    await t.pumpAndSettle();
    expect(find.text('Новый магазин'), findsOneWidget);
    expect(find.text('Точка отмечена, точность 12 м'), findsOneWidget);

    final save = find.text('Сохранить магазин');
    await tapVisible(t, save);
    await t.pumpAndSettle();
    expect(find.text('Введите название'), findsOneWidget);
    expect(find.text('Введите телефон'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Название *'), 'Магазин «Нур»');
    await t.enterText(find.widgetWithText(TextFormField, 'Телефон *'), '8 701 555 44');
    await t.enterText(find.widgetWithText(TextFormField, 'БИН / ИИН'), '1234');
    await tapVisible(t, save);
    await t.pumpAndSettle();
    expect(find.text('+7 и 10 цифр, например +7 701 123 45 67'), findsOneWidget);
    expect(find.text('12 цифр'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Телефон *'), '8 701 555 44 33');
    await t.enterText(find.widgetWithText(TextFormField, 'БИН / ИИН'), '123456789012');
    await tapVisible(t, save);
    await t.pump();
    expect(find.text('Укажите адрес или ориентир'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextFormField, 'Ориентир (в селе вместо адреса)'), 'у мечети');
    await tapVisible(t, find.text('Розница'));
    await tapVisible(t, find.text('Фото фасада'));
    await settleIo(t);
    expect(find.text('Переснять фасад'), findsOneWidget);

    server.offline = true;
    await tapVisible(t, save);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.text('Мой день'), findsOneWidget);
    expect(find.text('Магазин сохранён. После отправки он появится в маршруте «на проверке»'), findsOneWidget);
    expect(find.text('Новые магазины'), findsOneWidget);
    expect(find.text('Ждёт отправки · у мечети'), findsOneWidget);

    await t.tap(find.byTooltip('Меню'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Отправка · ждут'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.text('Новые магазины'), findsOneWidget);
    expect(find.text('Фото'), findsOneWidget);

    server.offline = false;
    await t.tap(find.text('Отправить сейчас'));
    await settleIo(t);
    expect(find.text('Всё отправлено'), findsOneWidget);
    final sent = server.outlets.values.single;
    expect([sent['name'], sent['phone'], sent['bin'], sent['landmark'], sent['priceKind'], sent['routeId'], sent['lat']],
        ['Магазин «Нур»', '8 701 555 44 33', '123456789012', 'у мечети', 'RETAIL', 1, 42.3]);
    expect(server.facades.values.single, FakeCamera.jpeg);

    await t.pageBack();
    await settleIo(t);
    expect(find.text('Новые магазины'), findsNothing);
    await t.scrollUntilVisible(find.text('Магазин «Нур»'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('на проверке'), findsOneWidget);
    expect(find.text('Центр · Шымкент · 3 магазина'), findsOneWidget);
  });

  testWidgets('карта: все магазины компании, филиал и «Мои», свой открывается', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    await t.tap(find.byTooltip('Карта'));
    await t.pumpAndSettle();
    expect(find.text('5 точек'), findsOneWidget);
    expect(find.text('Все филиалы'), findsOneWidget);

    await t.tap(find.text('Мои'));
    await t.pumpAndSettle();
    expect(find.text('3 точки'), findsOneWidget);
    await t.tap(find.text('Все'));
    await t.pumpAndSettle();
    await t.tap(find.text('Сайрам'));
    await t.pumpAndSettle();
    expect(find.text('2 точки'), findsOneWidget);

    await t.tap(find.byTooltip('Магазин «Ак жол»'));
    await t.pumpAndSettle();
    expect(find.text('Сайрам · магазин другого торгового'), findsOneWidget);
    expect(find.text('Открыть магазин'), findsNothing);
    await t.tapAt(const Offset(400, 50));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Магазин «Сайрам»'));
    await t.pumpAndSettle();
    expect(find.text('Сайрам · ваш магазин'), findsOneWidget);
    await t.tap(find.text('Открыть магазин'));
    await t.pumpAndSettle();
    expect(find.text('Начать визит'), findsOneWidget);
  });

  testWidgets('экспедитор: рейс по точкам, карточка точки — состав, долг, звонок и маршрут', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    expect(find.text('Рейс'), findsOneWidget);
    expect(find.text('Сегодня · Р-281026-1 · 245 AKS 02 · пройдено 1 из 2'), findsOneWidget);
    expect(find.text('З-271026-1 · ${money(13500)} · Наличные'), findsOneWidget);
    expect(find.text('Доставлен'), findsOneWidget);
    expect(find.text('долг ${money(45000)}, просрочено ${money(12000)}'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Магазин «Сайрам»'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('· Р-291026-1 · 245 AKS 02 · 1 точка'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Магазин «Арай»'), -200, scrollable: find.byType(Scrollable).first);

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    expect(find.text('Заказ З-271026-1'), findsOneWidget);
    expect(find.text('Комментарий: после обеда'), findsOneWidget);
    expect(find.text('24 шт × ${money(500)} · 2 кор.'), findsOneWidget);
    expect(find.text(money(12000)), findsOneWidget);
    expect(find.text('Долг ${money(45000)}'), findsOneWidget);
    expect(find.text('Позвонить'), findsOneWidget);
    expect(find.byTooltip('Накладная'), findsOneWidget);

    final opened = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
      opened.add((call.arguments as Map)['url'] as String);
      return opened.length == 1; // звонок открылся, карт на телефоне нет
    });
    await t.tap(find.text('Позвонить'));
    await t.pumpAndSettle();
    await t.tap(find.text('Маршрут'));
    await t.pumpAndSettle();
    expect(opened, ['tel:+77010000000', 'geo:42.3,69.6?q=42.3,69.6(${Uri.encodeComponent('Магазин «Арай»')})']);
    expect(find.text('На телефоне нет приложения карт'), findsOneWidget);
  });

  testWidgets('экспедитор: выдача частично — меньше товара, часть денег, остаток в долг; точка пройдена', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    await t.tap(find.text('Выдать'));
    await t.pumpAndSettle();
    expect(find.text('Сначала начните рабочий день на главном экране'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();

    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();
    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    await t.tap(find.text('Выдать'));
    await t.pumpAndSettle();
    expect(find.text('Выдача З-271026-1'), findsOneWidget);
    expect(find.text('Выдать на ${money(13500)}'), findsOneWidget);
    expect(find.widgetWithText(TextField, '13500'), findsOneWidget); // наличные — вся сумма

    await t.tap(find.byTooltip('Меньше').first);
    await t.pump();
    await t.tap(find.byTooltip('Меньше').first);
    await t.pump();
    expect(find.text('Выдать на ${money(12500)}'), findsOneWidget);
    expect(find.text('по заказу ${money(13500)}'), findsOneWidget);
    expect(find.widgetWithText(TextField, '12500'), findsOneWidget); // деньги идут за суммой

    await t.enterText(find.widgetWithText(TextField, 'Наличными'), '10000');
    await t.pump();
    expect(find.text('Остаток ${money(2500)} — в долг магазина'), findsOneWidget);
    await tapVisible(t, find.text('Выдать на ${money(12500)}'));
    await t.pumpAndSettle();

    expect(find.text('Выдача сохранена'), findsOneWidget);
    expect(find.text('Выдано частично на ${money(12500)}'), findsOneWidget);
    expect(find.text('наличными ${money(10000)} · в долг ${money(2500)}'), findsOneWidget);
    expect(find.textContaining('Отправлено'), findsOneWidget);
    expect(find.text('Выдать'), findsNothing);
    final sent = server.deliveries.values.single;
    expect(sent['items'], [
      {'productId': 1, 'qty': 22},
      {'productId': 2, 'qty': 5},
    ]);
    expect([for (final p in sent['payments'] as List) p['amount']], [10000]);

    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Сегодня · Р-281026-1 · 245 AKS 02 · пройдено 2 из 2'), findsOneWidget);
    expect(find.text('Частично'), findsOneWidget); // данные с сервера обновились после отправки
    expect(server.count('/api/mobile/expeditor/data'), 2);
  });

  testWidgets('экспедитор: отказ без сети ждёт отправки, его можно отменить', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();
    server.offline = true;

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    await t.tap(find.text('Отказ'));
    await t.pumpAndSettle();
    expect(t.widget<TextButton>(find.widgetWithText(TextButton, 'Отказ')).onPressed, isNull); // без причины
    await t.tap(find.text('Магазин закрыт'));
    await t.pump();
    await t.tap(find.widgetWithText(TextButton, 'Отказ'));
    await t.pumpAndSettle();

    expect(find.text('Отказ: Магазин закрыт'), findsOneWidget);
    expect(find.textContaining('Ждёт отправки'), findsOneWidget);
    expect(find.byTooltip('Накладная'), findsNothing); // отказ — накладной нет
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Отказ · ждёт отправки'), findsOneWidget);
    expect(find.textContaining('пройдено 2 из 2'), findsOneWidget);

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Отменить отказ'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Отменить'));
    await t.pumpAndSettle();
    expect(find.text('Отказ: Магазин закрыт'), findsNothing);
    expect(find.text('Выдать'), findsOneWidget);
    expect(server.deliveries, isEmpty);
  });

  testWidgets('экспедитор: оплата старого долга — наличные и Kaspi, долг на сервере уменьшился', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Оплата долга'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, '45000'), findsOneWidget); // весь долг наличными
    expect(find.text('Останется долг ${money(0)}'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextField, 'Наличными'), '50000');
    await t.pump();
    expect(find.text('Больше долга на ${money(5000)} — останется у магазина авансом'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Наличными'), '20000');
    await t.enterText(find.widgetWithText(TextField, 'Kaspi'), '5000');
    await t.pump();
    expect(find.text('Останется долг ${money(20000)}'), findsOneWidget);
    await t.tap(find.text('Принять ${money(25000)}'));
    await t.pumpAndSettle();

    expect(find.text('Оплата долга сохранена'), findsOneWidget);
    expect(find.textContaining('Принято в счёт долга ${money(20000)} наличными'), findsOneWidget);
    expect(find.textContaining('Принято в счёт долга ${money(5000)} Kaspi'), findsOneWidget);
    expect(find.textContaining('долг теперь ${money(20000)}'), findsOneWidget);
    expect(server.debtPayments, hasLength(2));

    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('долг ${money(20000)}, просрочено ${money(12000)}'), findsOneWidget);
  });

  testWidgets('экспедитор: возврат брака — товары из заказа сначала, причина, долг меньше', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();

    await t.tap(find.text('Магазин «Береке»'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Возврат'));
    await t.pumpAndSettle();
    expect(find.text('Магазин «Береке» · опт'), findsOneWidget);
    final names = t.widgetList<Text>(find.textContaining(RegExp('^(Печенье|Вафли|Торт)'))).map((w) => w.data).toList();
    expect(names, ['Печенье овсяное', 'Вафли сливочные', 'Торт «Наполеон»']); // из заказа — первым
    expect(find.text('нет цены'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Принять')).onPressed, isNull);

    await t.tap(find.text('Просрочка'));
    await t.tap(find.byTooltip('Вернуть Печенье овсяное'));
    await t.pump();
    await t.tap(find.byTooltip('Больше'));
    await t.pump();
    await t.tap(find.byTooltip('Вернуть Вафли сливочные'));
    await t.pump();
    expect(find.text('3 шт · долг меньше на'), findsOneWidget);
    expect(find.text(money(1300)), findsOneWidget);
    await t.tap(find.text('Принять'));
    await t.pumpAndSettle();

    expect(find.text('Возврат сохранён'), findsOneWidget);
    expect(find.textContaining('Возврат (просрочка) 3 шт на ${money(1300)}'), findsOneWidget);
    expect(find.textContaining('аванс ${money(1300)}'), findsOneWidget); // долга не было
    expect((server.returns.values.single['lines'] as List).map((l) => (l as Map)['reason']), ['EXPIRED', 'EXPIRED']);
  });

  testWidgets('экспедитор: «Итог дня» — что сдать в кассу, долг магазинам, товар в машине', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await t.tap(find.text('Начать день'));
    await t.pumpAndSettle();
    server.offline = true;
    await t.tap(find.text('Магазин «Береке»'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Оплата долга'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Наличными'), '4000');
    await t.pump();
    await t.tap(find.text('Принять ${money(4000)}'));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Итог дня'));
    await t.pumpAndSettle();
    expect(find.text('Сегодня · Р-281026-1 · 245 AKS 02'), findsOneWidget);
    expect(find.text('Пройдено 1 из 2'), findsOneWidget);
    expect(find.text('выдано 1 · не пройдено 1'), findsOneWidget);
    expect(find.text(money(4000)), findsWidgets); // наличные и из них в счёт долгов
    expect(find.text('из них в счёт долгов'), findsOneWidget);
    expect(find.text('29 шт'), findsOneWidget);
    expect(find.textContaining('Не отправлено на сервер: 1 запись'), findsOneWidget);

    server.offline = false;
    await t.tap(find.text('Отправить сейчас'));
    await t.pumpAndSettle();
    expect(find.textContaining('Не отправлено'), findsNothing);
    expect(server.debtPayments, hasLength(1));
  });
}
