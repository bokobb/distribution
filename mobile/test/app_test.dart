import 'dart:io';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/format.dart';
import 'package:distribution_mobile/location.dart';
import 'package:distribution_mobile/main.dart';
import 'package:distribution_mobile/session.dart';
import 'package:distribution_mobile/widgets/layout.dart';
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
  await t.enterText(find.byType(TextFormField).at(0), '87010000101');
  await t.enterText(find.byType(TextFormField).at(1), password);
  await tapVisible(t, find.text('Войти'));
  await t.pumpAndSettle();
}

/// Раздел внизу экрана: «Профиль», «Магазины», «Касса».
Future<void> openTab(WidgetTester t, String label) async {
  await t.tap(find.descendant(of: find.byType(AppTabBar), matching: find.text(label)));
  await t.pumpAndSettle();
}

/// Кнопка с этой надписью (а не такой же текст рядом: «Доставлено» — и итог, и кнопка).
Finder button(String label) =>
    find.descendant(of: find.byWidgetPredicate((w) => w is ButtonStyleButton), matching: find.text(label));

/// Поле суммы с этой подписью («Получено наличными», «В счёт старого долга»).
Finder moneyField(String label) => find.byWidgetPredicate((w) => w is MoneyInput && w.semanticLabel == label);

/// Внутри листа снизу («Добавить товар»), а не на экране под ним.
Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

/// Шапка раздела с этим заголовком на экране.
Finder header(String title) => find.widgetWithText(PageHeader, title);

/// «Профиль» → «Выйти из аккаунта» → «Выйти» в вопросе.
Future<void> logOut(WidgetTester t, {String? warning}) async {
  await openTab(t, 'Профиль');
  await tapVisible(t, find.text('Выйти из аккаунта'));
  await t.pumpAndSettle();
  if (warning != null) expect(find.textContaining(warning), findsOneWidget);
  await t.tap(find.widgetWithText(TextButton, 'Выйти'));
  await t.pumpAndSettle();
}

/// «Профиль» → плашка отправки → «Отправка».
Future<void> openSend(WidgetTester t) async {
  await openTab(t, 'Профиль');
  await t.tap(find.textContaining(RegExp('жд(ёт|ут) отправки')));
  await t.pumpAndSettle();
}

/// Прокрутить к виджету и нажать. Сначала дать полю ввода прокрутить к курсору — иначе оно уведёт прокрутку обратно.
/// Подсказка внизу (SnackBar) в тесте сама не уходит — время не идёт; на телефоне она уходит через 4 с, а здесь
/// закрывается, чтобы не загораживать кнопку.
Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.pumpAndSettle();
  final messenger = find.byType(ScaffoldMessenger);
  if (messenger.evaluate().isNotEmpty) t.state<ScaffoldMessengerState>(messenger.first).clearSnackBars();
  await t.pumpAndSettle();
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

/// «Подтверждение доставки» фото накладной.
Future<void> confirmByPhoto(WidgetTester t) async {
  expect(find.text('Подтверждение доставки'), findsOneWidget);
  await t.tap(find.text('Фото накладной'));
  await t.pump();
  expect(find.text('Нужно фото накладной с печатью'), findsOneWidget);
  await t.tap(find.text('Сфотографировать накладную'));
  await settleIo(t);
  expect(find.text('Фото накладной приложено'), findsOneWidget);
  await t.tap(find.text('Подтвердить доставку'));
  await t.pumpAndSettle();
  await settleIo(t, rounds: 3); // фото уходит вслед за выдачей: чтение и стирание файла
}

/// Дать отработать настоящему вводу-выводу (файл фото): каждый его шаг ждёт кадра.
Future<void> settleIo(WidgetTester t, {int rounds = 1}) async {
  for (var i = 0; i < 5 * rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    // подложка карты кладёт плитки в папку кеша — в тесте временная
    final cache = Directory.systemTemp.createTempSync('tiles').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => cache);
  });

  testWidgets('пустые поля: подсказки, на сервер не идём', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));

    await tapVisible(t, find.text('Войти'));
    await t.pump();

    expect(find.text('Введите телефон'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  testWidgets('агент входит — «Сегодня», ключ устройства сохранён', (t) async {
    final store = SessionStore();
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: FakeServer().client), store: store));

    await logIn(t);

    expect(header('Сегодня'), findsOneWidget);
    expect(find.text('${dayTitle(DateTime.now())} · Иван'), findsOneWidget);
    await openTab(t, 'Профиль');
    expect(find.text('Торговый представитель · Своя доставка'), findsOneWidget);
    expect(find.text('+7 701 000 01 01'), findsOneWidget);
    expect((await store.load())?.name, 'Иван');
    expect(await store.deviceToken(), 'ключ');
  });

  testWidgets('экспедитор входит — «Рейс»', (t) async {
    final api = ApiClient(baseUrl: 'http://s', client: FakeServer(role: 'EXPEDITOR').client);
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: api, store: SessionStore()));

    await logIn(t);

    expect(header('Доставки'), findsOneWidget);
  });

  testWidgets('отказ сервера показывается, вход не запоминается', (t) async {
    final store = SessionStore();
    final api = ApiClient(baseUrl: 'http://s', client: FakeServer(role: 'OPERATOR').client);
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: api, store: store));

    await logIn(t);

    expect(find.text('Оператор работает в веб-админке.'), findsOneWidget);
    expect(await store.load(), isNull);
  });

  testWidgets('временный пароль — сначала свой, потом «Сегодня»', (t) async {
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

    expect(header('Сегодня'), findsOneWidget);
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

    expect(header('Сегодня'), findsOneWidget);
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

    await logOut(t);

    expect(find.text('Войти'), findsOneWidget);
    expect(server.count('/api/mobile/auth/logout'), 1);
    expect(await store.load(), isNull);
    expect(await store.deviceToken(), isNull);
  });

  testWidgets('«Сегодня»: итоги дня; «Создать заказ» — магазин по GPS, рядом, поиск по всей базе', (t) async {
    final local = MemoryStore();
    final gps = FakeLocation();
    await t.pumpWidget(DistributionApp(location: gps, camera: FakeCamera(), local: local, api: ApiClient(baseUrl: 'http://s', client: FakeServer().client), store: SessionStore()));

    await logIn(t);

    expect(find.text('Создать заказ'), findsOneWidget);
    expect(find.text('Заказы за сегодня'), findsOneWidget);
    expect(find.text('0 заказов'), findsOneWidget);
    expect(find.text('Визитов пока нет — у магазина нажмите «Создать заказ»'), findsOneWidget);
    expect(find.text('Пн'), findsNothing); // маршрутов по дням нет
    expect(local.data['agent'], isNotNull);

    await tapVisible(t, find.text('Создать заказ'));
    await t.pump();
    expect(find.text('Сначала начните рабочий день'), findsOneWidget);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    expect(find.text('Магазин — по GPS или поиском'), findsOneWidget);
    gps.fix(DateTime.now());
    await t.pumpAndSettle();
    expect(find.text('Вы здесь: Магазин «Арай» · 0 м'), findsOneWidget);
    expect(find.text('Рабочий день начат в ${time(DateTime.now())}'), findsOneWidget);

    await tapVisible(t, find.text('Создать заказ'));
    await t.pumpAndSettle();
    expect(find.text('Вы сейчас у этого магазина'), findsOneWidget);
    expect(find.text('0 м · GPS 12 м'), findsOneWidget);
    expect(find.text('ИП Магазин «Арай» · ул. Байтурсынова, 1'), findsOneWidget);
    expect(find.text('Долг ${money(45000)}'), findsOneWidget);
    expect(find.text('Просрочено ${money(12000)}'), findsOneWidget);
    expect(find.text('Прошлый заказ 21 окт'), findsOneWidget);
    expect(find.text('Рядом'), findsOneWidget);
    expect(find.text('до 600 м · в базе 6 магазинов'), findsOneWidget);
    expect(find.text('Магазин «Береке»'), findsOneWidget);
    expect(find.text('Магазин «Сосед»'), findsNothing); // в 1,4 км

    await t.enterText(find.byType(TextField), 'сосед');
    await t.pump();
    expect(find.text('Найдено в базе'), findsOneWidget);
    expect(find.text('1 магазин'), findsOneWidget);
    expect(find.text('ул. Абая, 1 · Гульнара М.'), findsOneWidget); // чужой — без долга
    expect(find.textContaining('Долг'), findsNothing);
    await t.enterText(find.byType(TextField), 'кунаева');
    await t.pump();
    expect(find.text('Магазин «Без точки»'), findsOneWidget);
    expect(find.text('На проверке'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'нет такого');
    await t.pump();
    expect(find.text('В базе такого магазина нет — создайте его ниже'), findsOneWidget);
    expect(find.text('Новый магазин'), findsOneWidget);
  });

  testWidgets('без сети — данные с телефона и подсказка, когда обновляли', (t) async {
    final server = FakeServer()..offline = true;
    final local = MemoryStore()..data['agent'] = sampleAgentData();
    const s = Session(userId: 1, name: 'Иван', role: 'AGENT');
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: local, api: ApiClient(baseUrl: 'http://s', client: server.client, deviceToken: 'ключ'), store: SessionStore(), session: s));
    await t.pumpAndSettle();

    expect(find.text('Создать заказ'), findsOneWidget);
    expect(find.text('Нет связи с сервером. Данные сегодня в 09:15'), findsOneWidget);
  });

  testWidgets('«Магазины»: у кого стоите — карточка снизу; «Карточка» — долг, что берёт, история', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    await openTab(t, 'Магазины');
    expect(find.text('Магазин «Арай»'), findsOneWidget);
    expect(find.text('ул. Байтурсынова, 1 · вы у магазина'), findsOneWidget);
    expect(find.text('Просрочено ${money(12000)}'), findsOneWidget);
    expect(find.text('Долг ${money(45000)}'), findsOneWidget);

    await t.tap(find.text('Карточка'));
    await t.pumpAndSettle();
    expect(find.text('ИП Магазин «Арай» · ул. Байтурсынова, 1'), findsOneWidget);
    expect(find.text('Вы у магазина'), findsOneWidget);
    expect(find.text('Опт'), findsOneWidget);
    expect(find.text('В базе с марта 2025'), findsOneWidget);
    expect(find.byTooltip('Позвонить в магазин'), findsOneWidget);
    expect(find.text('Долг магазина'), findsOneWidget);
    expect(find.text('лимит ${money(100000)} · отсрочка 7 дней'), findsOneWidget);
    expect(find.text(money(45000)), findsOneWidget);
    expect(find.text('Просрочено ${money(12000)}'), findsOneWidget);
    expect(find.text('${money(30400)} · раз в неделю'), findsOneWidget);
    expect(find.text('3% от заказов · в основном срок годности'), findsOneWidget);
    expect(find.textContaining('Вафли сливочные · '), findsOneWidget);
    await t.scrollUntilVisible(find.text('30 сен · без заказа'), 200);
    expect(find.text('21 окт · заказ ${money(31680)}'), findsOneWidget);
    expect(find.text('возврат ${money(1240)} · упаковка'), findsOneWidget);
    expect(find.text('без возврата'), findsOneWidget);
    expect(find.text('Доставлен'), findsNWidgets(2));
    expect(find.text('товар ещё есть'), findsOneWidget);

    await t.scrollUntilVisible(find.text('Без заказа'), -200);
    await tapVisible(t, find.text('Без заказа'));
    await t.pump();
    expect(find.text('Сначала начните рабочий день на главном экране'), findsOneWidget);
  });

  testWidgets('выход стирает данные с телефона', (t) async {
    final local = MemoryStore()..data['agent'] = sampleAgentData();
    const s = Session(userId: 1, name: 'Иван', role: 'AGENT');
    await t.pumpWidget(DistributionApp(location: FakeLocation(), camera: FakeCamera(), local: local, api: ApiClient(baseUrl: 'http://s', client: FakeServer().client, deviceToken: 'ключ'), store: SessionStore(), session: s));
    await t.pumpAndSettle();

    await logOut(t);

    expect(local.data, isEmpty);
  });

  testWidgets('«Начать день» и выход: день закрывается, журнал уходит на сервер', (t) async {
    final server = FakeServer();
    final local = MemoryStore();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: local, api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    expect(find.text('Рабочий день не начат'), findsOneWidget);

    await t.tap(find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    expect(find.text('Рабочий день не начат'), findsNothing);
    expect(find.text('Путь пишется'), findsOneWidget);

    await logOut(t, warning: 'Рабочий день будет закончен.');
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

    await t.tap(find.text('Начать рабочий день'));
    await t.pump();

    expect(find.text('Разрешите приложению доступ к местоположению в настройках телефона'), findsOneWidget);
    expect(find.text('Рабочий день не начат'), findsOneWidget);
  });

  testWidgets('«Без заказа»: причина и комментарий — визит на сервер, в «Визитах сегодня»', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Создать заказ'));
    await t.pumpAndSettle();

    await t.tap(button('Без заказа'));
    await t.pumpAndSettle();
    expect(find.text('ул. Байтурсынова, 1 · почему сегодня без заказа?'), findsOneWidget);
    await tapVisible(t, find.text('Завершить визит'));
    await t.pump();
    expect(find.text('Выберите, почему без заказа'), findsOneWidget);

    await tapVisible(t, find.text('Другая причина'));
    await tapVisible(t, find.text('Завершить визит'));
    await t.pump();
    expect(find.text('Напишите причину в комментарии'), findsOneWidget);

    await tapVisible(t, find.text('Хозяина нет на месте'));
    await t.enterText(find.byType(TextField), 'зайти после обеда');
    await tapVisible(t, find.text('Завершить визит'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    expect(header('Сегодня'), findsOneWidget);
    expect(find.text('Без заказа · хозяина нет на месте — зайти после обеда'), findsOneWidget);
    expect(server.visits.values.single['refuseReason'], 'Хозяина нет на месте — зайти после обеда');
    expect(server.visits.values.single['result'], 'NO_ORDER');
  });

  testWidgets('заказ и возврат на одном экране: «Как 21 октября», коробки, возврат с причиной — к оплате меньше',
      (t) async {
    final server = FakeServer();
    // долг ближе к лимиту: в долг заказ уйдёт руководителю
    ((server.agentData['outlets'] as List).first as Map<String, dynamic>)['debt'] = 90000;
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Создать заказ'));
    await t.pumpAndSettle();
    await t.tap(find.text('Заказ здесь'));
    await t.pumpAndSettle();

    expect(find.text('вы у магазина · ул. Байтурсынова, 1'), findsOneWidget);
    expect(find.text('Просрочено ${money(12000)}'), findsOneWidget);
    expect(find.text('0 товаров в заказе\nна сумму ${money(0)}'), findsOneWidget);
    await t.tap(find.text('Как 21 октября'));
    await t.pumpAndSettle();
    expect(find.text('2 товара в заказе\nна сумму ${money(24000)}'), findsOneWidget); // 24 × 500 + 40 × 300
    expect(find.text('2 кор'), findsNWidgets(2));
    await t.tap(find.byTooltip('Добавить коробку').first);
    await t.pump();
    expect(find.text('36 шт · ${money(18000)}'), findsOneWidget);

    // «Добавить позицию»: торт без цены не выбрать, вафли — ещё коробка
    await tapVisible(t, find.text('Добавить позицию'));
    await t.pumpAndSettle();
    expect(find.text('нет цены'), findsOneWidget);
    await t.tap(find.text('Торт «Наполеон»'));
    await t.pump();
    expect(find.text('Выберите товар в списке'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Поиск товара'), '4870001');
    await t.pump();
    expect(inSheet(find.text('Печенье овсяное')), findsNothing);
    expect(find.text('в заказе 2 кор'), findsOneWidget);
    await t.tap(inSheet(find.text('Вафли сливочные')));
    await t.pump();
    await t.tap(find.text('В заказ · 1 кор'));
    await t.pumpAndSettle();
    expect(find.text('60 шт · ${money(18000)}'), findsOneWidget);

    // возврат: печенье, 3 штуки, брак → упаковка
    await t.tap(find.text('Возврат · 0'));
    await t.pumpAndSettle();
    expect(find.text('Возврата нет — если магазин отдаёт негодный товар, добавьте его'), findsOneWidget);
    await tapVisible(t, find.text('Добавить в возврат'));
    await t.pumpAndSettle();
    await t.tap(inSheet(find.text('Печенье овсяное')));
    await t.pump();
    await t.tap(find.text('Брак'));
    await t.tap(find.byTooltip('Больше'));
    await t.tap(find.byTooltip('Больше'));
    await t.pump();
    expect(find.text('−${money(1500)}'), findsOneWidget);
    await t.tap(find.text('В возврат · 3 шт'));
    await t.pumpAndSettle();
    expect(find.text('Возврат · 1'), findsOneWidget);
    expect(find.text('3 шт × ${money(500)} = −${money(1500)}'), findsOneWidget);
    await t.tap(find.text('Упаковка'));
    await t.pump();
    expect(find.text('Заказ ${amount(36000)} − возврат ${amount(1500)}'), findsOneWidget);
    expect(find.text(money(34500)), findsOneWidget);

    await t.tap(find.text('Далее'));
    await t.pumpAndSettle();
    expect(find.text('Оформление'), findsOneWidget);
    expect(find.text(money(36000)), findsOneWidget);
    expect(find.text('−${money(1500)}'), findsOneWidget);
    expect(find.text(money(34500)), findsOneWidget);
    expect(find.text('Доставка и сбор возврата'), findsOneWidget);
    expect(find.textContaining('Есть просрочка ${money(12000)}'), findsOneWidget);
    await t.tap(find.text('В долг'));
    await t.pump();
    // долг 90 000 + к оплате 34 500 больше лимита 100 000
    expect(
        find.text('Долг станет ${money(124500)} при лимите ${money(100000)}\n'
            'Заказ уйдёт руководителю на подтверждение. Предупредите магазин.'),
        findsOneWidget);
    await t.enterText(find.byType(TextField), 'вход со двора');
    await tapVisible(t, find.text('Отправить заказ и возврат'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    expect(header('Сегодня'), findsOneWidget);
    expect(find.text('1 заказ'), findsOneWidget);
    // итог сервера: 96 шт × 500, возврат 3 × 500
    expect(find.text('Заказ ${money(48000)} · возврат ${money(1500)}'), findsOneWidget);
    final sent = server.orders.values.single;
    expect(sent['items'], [{'productId': 1, 'qty': 36}, {'productId': 2, 'qty': 60}]);
    expect(sent['returns'], [{'productId': 1, 'qty': 3, 'reason': 'PACKAGING'}]);
    expect([sent['payment'], sent['comment']], ['CREDIT', 'вход со двора']);
    expect(sent['visitUuid'], server.visits.keys.single);
  });

  testWidgets('заказ в магазине другого торгового: без долгов, по его прайсу; идёт визит — «Продолжить заказ»',
      (t) async {
    final gps = FakeLocation()..here = Fix(at: DateTime(2026, 10, 28, 10), lat: 42.31, lng: 69.61, accuracy: 5);
    await t.pumpWidget(DistributionApp(
        location: gps, camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: FakeServer().client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Создать заказ'));
    await t.pumpAndSettle();

    expect(find.text('Гульнара М. · ул. Абая, 1'), findsOneWidget);
    await t.tap(find.text('Заказ здесь'));
    await t.pumpAndSettle();
    expect(find.textContaining('Долг'), findsNothing);
    await tapVisible(t, find.text('Добавить позицию'));
    await t.pumpAndSettle();
    expect(inSheet(find.text('${money(600)} / шт · 12 шт в кор')), findsOneWidget); // розница
    await t.tap(inSheet(find.text('Печенье овсяное')));
    await t.pump();
    await t.tap(find.text('В заказ · 1 кор'));
    await t.pumpAndSettle();
    expect(find.text(money(7200)), findsOneWidget);

    // вышел с экрана — визит идёт, заказ в черновике
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Продолжить заказ'), findsOneWidget);
    expect(find.text('Идёт визит: Магазин «Сосед» — продолжить'), findsOneWidget);
    await tapVisible(t, find.text('Продолжить заказ'));
    await t.pumpAndSettle();
    expect(find.text(money(7200)), findsOneWidget);
  });

  testWidgets('«Отправка»: без сети ждёт, «Отправить сейчас» отправляет', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    server.offline = true;
    await t.tap(find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    await openSend(t);
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

  testWidgets('новый магазин: форма, сразу заказ без долга; без сети ждёт, после отправки — с номером сервера', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Создать заказ'));
    await t.pumpAndSettle();

    await tapVisible(t, find.text('Новый магазин'));
    await t.pumpAndSettle();
    expect(find.text('Магазина нет в базе — заполните на месте'), findsOneWidget);
    expect(find.text('Точка по GPS · точность 12 м'), findsOneWidget);
    expect(find.text('рядом: ул. Байтурсынова, 1'), findsOneWidget);
    expect(find.text('Не хватает: название, телефон, адрес, фото фасада'), findsOneWidget);
    final create = find.widgetWithText(FilledButton, 'Создать и оформить заказ');
    expect(t.widget<FilledButton>(create).onPressed, isNull);

    // поле по подсказке в нём; список строит только видимое — сначала прокрутить
    Future<void> type(String hint, String text) async {
      final f = find.widgetWithText(TextField, hint).first;
      await t.scrollUntilVisible(f, 100, scrollable: find.byType(Scrollable).first);
      await t.enterText(f, text);
      await t.pump();
    }

    await type('Например, «Береке-2»', 'Магазин «Нур»');
    await type('+7 7__ ___ __ __', '8 701 555 44');
    expect(find.text('+7 и 10 цифр, например +7 701 123 45 67'), findsOneWidget);
    await type('+7 7__ ___ __ __', '8 701 555 44 33');
    await type('Имя продавца или хозяина', 'Айдос Н.');
    await type('Улица, дом — напротив чего', 'у мечети');
    await tapVisible(t, find.text('Розница'));
    await tapVisible(t, find.text('Фото фасада *'));
    await settleIo(t);
    expect(find.text('Фото есть'), findsOneWidget);
    expect(find.text('Магазин сразу появится у вас, руководитель проверит'), findsOneWidget);

    server.offline = true;
    await tapVisible(t, create);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.text('Магазин «Нур»'), findsOneWidget); // заказ — сразу в нём
    await tapVisible(t, find.text('Добавить позицию'));
    await t.pumpAndSettle();
    expect(inSheet(find.text('${money(600)} / шт · 12 шт в кор')), findsOneWidget); // розница
    await t.tap(inSheet(find.text('Печенье овсяное')));
    await t.pump();
    await t.tap(find.text('В заказ · 1 кор'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Далее'));
    await t.pumpAndSettle();
    expect(find.text('В долг'), findsNothing); // первый заказ нового магазина — без долга
    await tapVisible(t, find.text('Отправить заказ'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    expect(header('Сегодня'), findsOneWidget);
    expect(find.text('Новые магазины'), findsOneWidget);
    expect(find.text('Ждёт отправки · у мечети'), findsOneWidget);
    expect(find.text('Магазин «Нур»'), findsNWidgets(2)); // и в «Визитах сегодня»

    server.offline = false;
    await openSend(t);
    await t.tap(find.text('Отправить сейчас'));
    await settleIo(t, rounds: 2);
    expect(find.text('Всё отправлено'), findsOneWidget);
    final sent = server.outlets.values.single;
    expect([sent['name'], sent['phone'], sent['owner'], sent['address'], sent['priceKind'], sent['routeId'], sent['lat']],
        ['Магазин «Нур»', '8 701 555 44 33', 'Айдос Н.', 'у мечети', 'RETAIL', 1, 42.3]);
    expect(server.facades.values.single, FakeCamera.jpeg);
    expect(server.visits.values.single['outletId'], 100);
    expect([server.orders.values.single['outletId'], server.orders.values.single['payment']], [100, 'CASH']);

    await t.pageBack();
    await settleIo(t);
    await openTab(t, 'Сегодня');
    expect(find.text('Новые магазины'), findsNothing);
    expect(find.text('Магазин «Нур»'), findsOneWidget);
  });

  testWidgets('«Магазины»: фильтры с числом, поиск по карте, список с фильтрами, чужой — без долга', (t) async {
    final server = FakeServer();
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    await openTab(t, 'Магазины');
    Finder chip(String text) => find.text(text, findRichText: true);
    expect(chip('Все  6'), findsOneWidget);
    expect(chip('Не был 7+ дней  3'), findsOneWidget); // «Береке» 10 дней, «Сайрам» ни разу, «Ак жол» 8 дней
    expect(chip('Просрочка  1'), findsOneWidget);
    expect(chip('Новые  1'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'ак жол');
    await t.pumpAndSettle();
    expect(find.text('1 магазин на карте'), findsOneWidget);
    expect(find.text('Магазин «Ак жол»'), findsOneWidget);
    expect(find.text('Средний заказ ${money(13900)}'), findsOneWidget);
    expect(find.text('Не был 8 дней'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'нет такого');
    await t.pumpAndSettle();
    expect(find.text('В базе такого нет'), findsOneWidget);
    expect(find.text('Создать новый'), findsOneWidget);

    await t.tap(find.text('Список'));
    await t.pumpAndSettle();
    expect(find.text('6 в базе · ближние сверху'), findsOneWidget);
    expect(find.text('Магазин «Сосед»'), findsOneWidget);
    await t.tap(find.text('С долгом'));
    await t.pumpAndSettle();
    expect(find.text('Магазин «Арай»'), findsOneWidget);
    expect(find.text('Просрочено ${money(12000)}'), findsOneWidget);
    expect(find.text('Магазин «Береке»'), findsNothing);
    await t.tap(find.text('Новые'));
    await t.pumpAndSettle();
    expect(find.text('Магазин «Без точки»'), findsOneWidget);
    expect(find.text('На проверке'), findsOneWidget);
    await t.tap(find.text('Рядом'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'сосед');
    await t.pumpAndSettle();
    await t.tap(find.text('Магазин «Сосед»'));
    await t.pumpAndSettle();
    expect(find.text('Гульнара М. · ул. Абая, 1'), findsOneWidget);
    expect(find.text('Розница'), findsOneWidget);
    expect(find.text('Долг магазина'), findsNothing); // чужой
    expect(find.byTooltip('Позвонить в магазин'), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Карта'));
    await t.pumpAndSettle();
    expect(chip('Все  6'), findsOneWidget);
  });

  testWidgets('экспедитор: «Доставки» — следующая точка раскрыта, звонок и «Поехали», доставленные и завтрашний рейс',
      (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    expect(header('Доставки'), findsOneWidget);
    expect(find.textContaining('245\u00a0AKS\u00a002'), findsOneWidget); // номер машины не рвётся
    expect(find.text('Маршрут'), findsOneWidget);
    expect(find.text('Новые · 1'), findsOneWidget);
    expect(find.text('Доставлены · 1'), findsOneWidget);
    expect(find.text('Следующая'), findsOneWidget);
    expect(find.text('ул. Байтурсынова, 1 · 2 позиции'), findsOneWidget);
    expect(find.text('Комментарий: после обеда'), findsOneWidget);
    expect(find.text('К оплате · Наличные'), findsOneWidget);
    expect(find.text(money(13500)), findsOneWidget);
    expect(find.text('Введите сумму, которую передал магазин'), findsOneWidget);
    expect(find.text('Принять старый долг'), findsOneWidget);
    expect(find.text(money(45000)), findsOneWidget);

    final opened = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
      opened.add((call.arguments as Map)['url'] as String);
      return opened.length == 1; // звонок открылся, карт на телефоне нет
    });
    await tapVisible(t, find.text('Звонок'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Поехали'));
    await t.pumpAndSettle();
    expect(opened, ['tel:+77010000000', 'geo:42.3,69.6?q=42.3,69.6(${Uri.encodeComponent('Магазин «Арай»')})']);
    expect(find.text('На телефоне нет приложения карт'), findsOneWidget);

    await t.scrollUntilVisible(find.text('Магазин «Сайрам»'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('· Р-291026-1 · 1 точка'), findsOneWidget);
    expect(find.text('${money(12000)} · Kaspi'), findsOneWidget);

    await t.scrollUntilVisible(find.text('Доставлены · 1'), -200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Доставлены · 1'));
    await t.pumpAndSettle();
    expect(find.text('Магазин «Арай»'), findsNothing);
    expect(find.text('В долг · ${money(5000)}'), findsOneWidget);
    await t.tap(find.text('Магазин «Береке»'));
    await t.pumpAndSettle();
    expect(find.text('Заказ З-271026-2'), findsOneWidget);
    expect(find.byTooltip('Накладная'), findsOneWidget);
  });

  testWidgets('экспедитор: «Маршрут» — точки на карте, следующая внизу, «Открыть» раскрывает её', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    await t.tap(find.text('Маршрут'));
    await t.pumpAndSettle();
    expect(find.text('1 точка'), findsOneWidget);
    expect(find.text('Следующая точка · 1'), findsOneWidget);
    expect(find.text('Магазин «Арай»'), findsOneWidget);
    expect(find.text(money(13500)), findsOneWidget);
    await t.tap(find.text('Открыть'));
    await t.pumpAndSettle();
    expect(header('Доставки'), findsOneWidget);
    expect(find.text('Следующая'), findsOneWidget);
  });

  testWidgets('экспедитор: «Состав» — выдать меньше, часть денег, остаток в долг; все доставлены — к кассе', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);

    await tapVisible(t, button('Доставлено'));
    await t.pump();
    expect(find.text('Сначала начните рабочий день на главном экране'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Начать рабочий день'), -200, scrollable: find.byType(Scrollable).first);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();

    await tapVisible(t, find.text('Состав'));
    await t.pumpAndSettle();
    expect(find.text('Заказ З-271026-1'), findsOneWidget);
    expect(find.text('Отдаём магазину'), findsOneWidget);
    expect(find.text('2 кор'), findsOneWidget); // 24 печенья по 12 в коробке
    expect(find.text('5 шт'), findsOneWidget); // вафель меньше коробки — по штуке
    expect(find.byTooltip('Больше на коробку'), findsOneWidget);
    await t.tap(find.byTooltip('Больше на коробку')); // больше заказанного нельзя
    await t.pump();
    expect(find.text('2 кор'), findsOneWidget);

    await t.tap(find.byTooltip('Меньше на коробку'));
    await t.pump();
    await t.tap(find.byTooltip('Меньше на штуку'));
    await t.pump();
    expect(find.text('было 2 кор · сейчас 12 шт · ${money(6000)}'), findsOneWidget);
    expect(find.text('было 5 шт · сейчас 4 шт · ${money(1200)}'), findsOneWidget);
    expect(find.text(money(7200)), findsOneWidget);
    await t.tap(find.text('Готово'));
    await t.pumpAndSettle();

    expect(find.text('К оплате · Наличные · выдаётся не всё'), findsOneWidget);
    expect(find.text(money(7200)), findsOneWidget);
    await t.enterText(moneyField('Получено наличными'), '9000');
    await t.pump();
    expect(find.text('Больше суммы заказа на ${money(1800)}'), findsOneWidget);
    await tapVisible(t, button('Доставлено'));
    await t.pump();
    expect(find.text('Получено больше, чем к оплате, на ${money(1800)}'), findsOneWidget);
    expect(server.deliveries, isEmpty);

    await t.enterText(moneyField('Получено наличными'), '5000');
    await t.pump();
    expect(find.text('Не хватает ${money(2200)} — останется долгом'), findsOneWidget);
    await tapVisible(t, button('Доставлено'));
    await t.pumpAndSettle();
    expect(find.text(money(5000)), findsOneWidget); // за заказ
    await t.pageBack(); // передумал — ничего не записано
    await t.pumpAndSettle();
    expect(server.deliveries, isEmpty);
    await tapVisible(t, button('Доставлено'));
    await t.pumpAndSettle();
    await confirmByPhoto(t);

    final sent = server.deliveries.values.single;
    expect(sent['items'], [
      {'productId': 1, 'qty': 12},
      {'productId': 2, 'qty': 4},
    ]);
    expect([for (final p in sent['payments'] as List) p['amount']], [5000]);
    expect(server.proofs[sent['uuid']]!.$1, 'image/jpeg');
    expect(server.count('/api/mobile/expeditor/data'), 2); // после отправки данные обновились
    expect(find.text('Новые · 0'), findsOneWidget);
    expect(find.text('Все доставки выполнены'), findsOneWidget);
    expect(button('Доставлено'), findsNothing); // все пройдены

    await t.tap(find.text('Доставлены · 2'));
    await t.pumpAndSettle();
    expect(find.text('Наличные · ${money(5000)}'), findsOneWidget);
    expect(find.text('Частично'), findsOneWidget);

    await t.tap(find.text('Новые · 0'));
    await t.pumpAndSettle();
    await t.tap(find.text('Перейти к сдаче кассы'));
    await t.pumpAndSettle();
    expect(header('Касса'), findsOneWidget);
  });

  testWidgets('экспедитор: «Вся сумма» и старый долг вместе с выдачей', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();

    await tapVisible(t, find.text('Вся сумма'));
    await t.pump();
    expect(find.widgetWithText(TextField, '13500'), findsOneWidget);
    expect(find.text('Сумма совпадает с заказом'), findsOneWidget);

    await tapVisible(t, find.text('Принять старый долг'));
    await t.pump();
    expect(find.text('В счёт старого долга'), findsWidgets);
    await tapVisible(t, find.text('Весь долг'));
    await t.pump();
    expect(find.text('Долг закрыт полностью'), findsOneWidget);
    await t.enterText(moneyField('В счёт старого долга'), '50000');
    await t.pump();
    expect(find.text('Больше долга на ${money(5000)} — уйдёт авансом'), findsOneWidget);
    await t.enterText(moneyField('В счёт старого долга'), '20000');
    await t.pump();
    expect(find.text('Останется долг ${money(25000)}'), findsOneWidget);
    expect(find.text('всего ${money(33500)}'), findsOneWidget);
    await tapVisible(t, button('Доставлено'));
    await t.pumpAndSettle();

    expect(find.text('Старый долг'), findsOneWidget);
    expect(find.text(money(33500)), findsOneWidget); // всего
    expect(find.text('Подтверждение доставки'), findsOneWidget);
    expect(find.text('Нужна подпись получателя'), findsOneWidget);
    expect(t.widget<ButtonStyleButton>(find.ancestor(of: find.text('Подтвердить доставку'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))).onPressed, isNull);
    await t.drag(find.text('Распишитесь здесь пальцем'), const Offset(120, 30));
    await t.pump();
    expect(find.text('Подпись получена'), findsOneWidget);
    await t.tap(find.text('Очистить'));
    await t.pump();
    expect(find.text('Нужна подпись получателя'), findsOneWidget);
    await t.drag(find.text('Распишитесь здесь пальцем'), const Offset(-100, 20));
    await t.pump();
    await t.tap(find.text('Подтвердить доставку'));
    await settleIo(t, rounds: 4); // картинка подписи, файл, выдача, отправка с подписью

    expect([for (final p in server.deliveries.values.single['payments'] as List) p['amount']], [13500]);
    expect([for (final p in server.debtPayments.values) p['amount']], [20000]);
    final proof = server.proofs.values.single;
    expect(proof.$1, 'image/png');
    expect(proof.$2.take(4), [0x89, 0x50, 0x4E, 0x47]); // PNG
    await openTab(t, 'Касса');
    expect(find.text(money(33500)), findsOneWidget);
    expect(find.text('из них в счёт долгов ${money(20000)}'), findsOneWidget);
    expect(find.textContaining('в счёт долга · наличные'), findsOneWidget);
  });

  testWidgets('экспедитор: отказ без сети ждёт отправки, его можно отменить', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    server.offline = true;

    await tapVisible(t, find.widgetWithText(TextButton, 'Магазин отказался'));
    await t.pumpAndSettle();
    expect(t.widget<TextButton>(find.widgetWithText(TextButton, 'Отказ')).onPressed, isNull); // без причины
    await t.tap(find.text('Магазин закрыт'));
    await t.pump();
    await t.tap(find.widgetWithText(TextButton, 'Отказ'));
    await t.pumpAndSettle();

    expect(find.text('Магазин «Арай» — отказ сохранён'), findsOneWidget);
    expect(find.text('Все доставки выполнены'), findsOneWidget);
    await t.tap(find.text('Доставлены · 2'));
    await t.pumpAndSettle();
    expect(find.text('Отказ: Магазин закрыт'), findsOneWidget);
    expect(find.text('ждёт отправки'), findsOneWidget);

    await t.tap(find.text('Магазин «Арай»'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Накладная'), findsNothing); // отказ — накладной нет
    await tapVisible(t, find.text('Отменить отказ'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Отменить'));
    await t.pumpAndSettle();
    // и из карточки точки выдача — тоже с подтверждением
    await t.scrollUntilVisible(find.text('Выдать'), -200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Выдать'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('Выдать на ${money(13500)}'));
    await t.pumpAndSettle();
    expect(find.text('Подтверждение доставки'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Доставлены · 1'), findsOneWidget);
    await t.tap(find.text('Новые · 1'));
    await t.pumpAndSettle();
    expect(button('Доставлено'), findsOneWidget);
    expect(server.deliveries, isEmpty);
  });

  testWidgets('экспедитор: «Состав» → возврат брака — товары из заказа сначала, к оплате меньше', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();

    await tapVisible(t, find.text('Состав'));
    await t.pumpAndSettle();
    expect(find.text('Забираем негодный товар'), findsOneWidget);
    await t.tap(find.text('Добавить'));
    await t.pumpAndSettle();
    expect(find.text('Магазин «Арай» · опт'), findsOneWidget);
    final names = t.widgetList<Text>(find.textContaining(RegExp('^(Печенье|Вафли|Торт)'))).map((w) => w.data).toList();
    expect(names, ['Вафли сливочные', 'Печенье овсяное', 'Торт «Наполеон»']); // из заказа — первыми
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
    expect(find.text('2 шт · просрочка'), findsOneWidget);
    expect(find.text('−${money(1000)}'), findsOneWidget);
    expect(find.text('1 шт · просрочка'), findsOneWidget);
    expect(find.text('${amount(13500)} − возврат ${amount(1300)}'), findsOneWidget);
    expect(find.text(money(12200)), findsOneWidget);
    expect((server.returns.values.single['lines'] as List).map((l) => (l as Map)['reason']), ['EXPIRED', 'EXPIRED']);

    await tapVisible(t, find.text('Готово'));
    await t.pumpAndSettle();
    expect(find.text('К оплате · Наличные'), findsOneWidget);
    expect(find.text(money(12200)), findsOneWidget);
  });

  testWidgets('экспедитор: возврат, записанный торговым, — подсказка на точке, «Забрать по списку» в «Составе»',
      (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    final stop = (((server.expeditorData['trips'] as List).first as Map)['stops'] as List).first as Map;
    (stop['order'] as Map)['returns'] = [
      {'productId': 1, 'name': 'Печенье овсяное', 'qty': 2, 'price': 500, 'reason': 'EXPIRED'},
      {'productId': 2, 'name': 'Вафли сливочные', 'qty': 3, 'price': 300, 'reason': 'DEFECT'},
    ];
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();

    expect(find.text('Магазин отдаёт возврат на ${money(1900)} — заберите в «Составе», сумма вычтется'), findsOneWidget);
    await tapVisible(t, find.text('Состав'));
    await t.pumpAndSettle();
    expect(find.text('Торговый Айгерим записал с заказом:'), findsOneWidget);
    expect(find.text('2 шт · просрочка'), findsOneWidget);
    expect(find.text('3 шт · брак'), findsOneWidget);
    await tapVisible(t, find.text('Забрать по списку · −${money(1900)}'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();

    expect(find.text('Возврат по списку торгового записан'), findsOneWidget);
    expect(find.text('Торговый Айгерим записал с заказом:'), findsNothing);
    expect(find.text('${amount(13500)} − возврат ${amount(1900)}'), findsOneWidget);
    // по возврату на причину
    final sent = server.returns.values.map((r) => [for (final l in r['lines'] as List) '${(l as Map)['productId']}:${l['qty']}:${l['reason']}']);
    expect(sent, unorderedEquals([['1:2:EXPIRED'], ['2:3:DEFECT']]));

    await tapVisible(t, find.text('Готово'));
    await t.pumpAndSettle();
    expect(find.textContaining('Магазин отдаёт возврат'), findsNothing);
    expect(find.text(money(11600)), findsOneWidget);
  });

  testWidgets('экспедитор: «Касса» — наличные, в счёт долгов, товар в машине; «Сдача кассы» по купюрам', (t) async {
    final server = FakeServer(role: 'EXPEDITOR');
    await t.pumpWidget(DistributionApp(
        location: FakeLocation(), camera: FakeCamera(), local: MemoryStore(), api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));
    await logIn(t);
    await tapVisible(t, find.text('Начать рабочий день'));
    await t.pumpAndSettle();
    server.offline = true;
    await t.tap(find.text('Доставлены · 1'));
    await t.pumpAndSettle();
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

    await openTab(t, 'Касса');
    expect(find.textContaining('доставлено 1 из 2'), findsOneWidget);
    expect(find.text(money(4000)), findsWidgets); // на руках и в «Получено по заказам»
    expect(find.text('из них в счёт долгов ${money(4000)}'), findsOneWidget);
    expect(find.text('ожидается ${money(17500)}'), findsOneWidget); // 4 000 + 13 500 у «Арая»
    expect(find.text('Магазин «Береке»'), findsOneWidget);
    expect(find.text('29 шт'), findsOneWidget);
    expect(find.textContaining('Не отправлено на сервер: 1 запись'), findsOneWidget);

    server.offline = false;
    await tapVisible(t, find.text('Отправить сейчас'));
    await t.pumpAndSettle();
    expect(find.textContaining('Не отправлено'), findsNothing);
    expect(server.debtPayments, hasLength(1));

    await tapVisible(t, find.text('Сдать кассу оператору'));
    await t.pumpAndSettle();
    expect(find.text('Нужно сдать'), findsOneWidget);
    expect(find.text('Не хватает ${money(4000)} — пересчитайте'), findsOneWidget);
    await t.tap(find.byTooltip('Добавить купюру ${amount(2000)}'));
    await t.pump();
    await t.tap(find.byTooltip('Добавить купюру ${amount(2000)}'));
    await t.pump();
    expect(find.text('Сходится с суммой к сдаче'), findsOneWidget);
    expect(find.text('2 купюры'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, '50');
    await t.pump();
    expect(find.text('Лишние ${money(50)} — проверьте купюры'), findsOneWidget);
    expect(find.text('Расхождение ${money(50)} попадёт в акт приёма'), findsOneWidget);
    await tapVisible(t, find.text('Сбросить'));
    await t.pump();
    expect(find.text('Сдать ${money(0)}'), findsOneWidget); // внизу всегда видно
    expect(find.text('Расхождение ${money(4000)} попадёт в акт приёма'), findsOneWidget);
  });
}
