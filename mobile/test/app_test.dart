import 'dart:convert';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:distribution_mobile/main.dart';
import 'package:distribution_mobile/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

ApiClient serverAnswering(String role) => ApiClient(
      baseUrl: 'http://server',
      client: MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'user': {'id': 1, 'name': 'Иван', 'role': role, 'company': 'Своя доставка'}
          })),
          200)),
    );

Future<void> logIn(WidgetTester t) async {
  await t.enterText(find.widgetWithText(TextFormField, 'Телефон или логин'), '87010000101');
  await t.enterText(find.widgetWithText(TextFormField, 'Пароль'), 'пароль');
  await t.tap(find.text('Войти'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('пустые поля: подсказки, на сервер не идём', (t) async {
    var calls = 0;
    final api = ApiClient(baseUrl: 'http://server', client: MockClient((_) async {
      calls++;
      return http.Response('', 500);
    }));
    await t.pumpWidget(DistributionApp(api: api, store: SessionStore()));

    await t.tap(find.text('Войти'));
    await t.pump();

    expect(find.text('Введите телефон или логин'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('агент входит — «Мой день», вход запомнен', (t) async {
    final store = SessionStore();
    await t.pumpWidget(DistributionApp(api: serverAnswering('AGENT'), store: store));

    await logIn(t);

    expect(find.text('Мой день'), findsOneWidget);
    expect(find.text('Иван · Своя доставка'), findsOneWidget);
    expect((await store.load())?.name, 'Иван');
  });

  testWidgets('экспедитор входит — «Рейс»', (t) async {
    await t.pumpWidget(DistributionApp(api: serverAnswering('EXPEDITOR'), store: SessionStore()));

    await logIn(t);

    expect(find.text('Рейс'), findsOneWidget);
  });

  testWidgets('оператор в приложение не входит', (t) async {
    final store = SessionStore();
    await t.pumpWidget(DistributionApp(api: serverAnswering('OPERATOR'), store: store));

    await logIn(t);

    expect(find.textContaining('работают в веб-админке'), findsOneWidget);
    expect(await store.load(), isNull);
  });

  testWidgets('выход возвращает на вход и забывает сотрудника', (t) async {
    final store = SessionStore();
    const s = Session(userId: 1, name: 'Иван', role: 'AGENT');
    await store.save(s);
    await t.pumpWidget(DistributionApp(api: serverAnswering('AGENT'), store: store, session: s));

    await t.tap(find.byTooltip('Меню'));
    await t.pumpAndSettle();
    await t.tap(find.text('Выйти'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Выйти'));
    await t.pumpAndSettle();

    expect(find.text('Войти'), findsOneWidget);
    expect(await store.load(), isNull);
  });
}
