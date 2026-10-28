import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/main.dart';
import 'package:distribution_mobile/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

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
    await t.pumpWidget(DistributionApp(api: ApiClient(baseUrl: 'http://s', client: server.client), store: SessionStore()));

    await t.tap(find.text('Войти'));
    await t.pump();

    expect(find.text('Введите телефон или логин'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  testWidgets('агент входит — «Мой день», ключ устройства сохранён', (t) async {
    final store = SessionStore();
    await t.pumpWidget(DistributionApp(api: ApiClient(baseUrl: 'http://s', client: FakeServer().client), store: store));

    await logIn(t);

    expect(find.text('Мой день'), findsOneWidget);
    expect(find.text('Иван · Своя доставка'), findsOneWidget);
    expect((await store.load())?.name, 'Иван');
    expect(await store.deviceToken(), 'ключ');
  });

  testWidgets('экспедитор входит — «Рейс»', (t) async {
    final api = ApiClient(baseUrl: 'http://s', client: FakeServer(role: 'EXPEDITOR').client);
    await t.pumpWidget(DistributionApp(api: api, store: SessionStore()));

    await logIn(t);

    expect(find.text('Рейс'), findsOneWidget);
  });

  testWidgets('отказ сервера показывается, вход не запоминается', (t) async {
    final store = SessionStore();
    final api = ApiClient(baseUrl: 'http://s', client: FakeServer(role: 'OPERATOR').client);
    await t.pumpWidget(DistributionApp(api: api, store: store));

    await logIn(t);

    expect(find.text('Оператор работает в веб-админке.'), findsOneWidget);
    expect(await store.load(), isNull);
  });

  testWidgets('временный пароль — сначала свой, потом «Мой день»', (t) async {
    final server = FakeServer(mustChange: true);
    final store = SessionStore();
    await t.pumpWidget(DistributionApp(api: ApiClient(baseUrl: 'http://s', client: server.client), store: store));

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

    await t.pumpWidget(DistributionApp(api: api, store: store, session: s));
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

    await t.pumpWidget(DistributionApp(api: api, store: SessionStore(), session: s));
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
    await t.pumpWidget(DistributionApp(api: api, store: store, session: s));
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
}
