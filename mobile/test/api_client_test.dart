import 'dart:convert';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_server.dart';

void main() {
  test('вход: ключ устройства запомнен, дальше запросы с JWT', () async {
    final server = FakeServer();
    final api = ApiClient(baseUrl: 'http://server', client: server.client, device: 'Samsung SM-A515F', appVersion: '1.0.0+1');

    final s = await api.login('87010000101', 'пароль');
    final me = await api.me();

    expect(jsonDecode(server.requests.first.body),
        {'login': '87010000101', 'password': 'пароль', 'device': 'Samsung SM-A515F', 'appVersion': '1.0.0+1'});
    expect(s.name, 'Иван');
    expect(s.isAgent, isTrue);
    expect(api.deviceToken, 'ключ');
    expect(me.company, 'Своя доставка');
    expect(server.count('/api/mobile/auth/refresh'), 0);
  });

  test('JWT истёк — новый по ключу устройства, запрос повторяется', () async {
    final server = FakeServer();
    final api = ApiClient(baseUrl: 'http://server', client: server.client);
    await api.login('x', 'пароль');

    server.expireJwt();
    final me = await api.me();

    expect(me.name, 'Иван');
    expect(server.count('/api/mobile/auth/refresh'), 1);
    expect(server.count('/api/mobile/me'), 2);
  });

  test('после запуска приложения JWT нет — сначала берётся по ключу', () async {
    final server = FakeServer();
    final api = ApiClient(baseUrl: 'http://server', client: server.client, deviceToken: 'ключ');

    await api.me();

    expect(server.requests.map((r) => r.url.path), ['/api/mobile/auth/refresh', '/api/mobile/me']);
  });

  test('ключ закрыт на сервере — вход закрыт, ключ забыт', () async {
    final server = FakeServer()..keyOpen = false;
    String? closed;
    final api = ApiClient(baseUrl: 'http://server', client: server.client, deviceToken: 'ключ')
      ..onSessionClosed = (m) => closed = m;

    await expectLater(api.me(), throwsA(isA<SessionClosedException>()));

    expect(closed, 'Вход на этом телефоне закрыт — войдите с паролем');
    expect(api.deviceToken, isNull);
  });

  test('выход: ключ закрывается на сервере; без сети — просто забывается', () async {
    final server = FakeServer();
    final api = ApiClient(baseUrl: 'http://server', client: server.client, deviceToken: 'ключ');

    await api.logout();
    expect(jsonDecode(server.requests.single.body), {'deviceToken': 'ключ'});
    expect(api.deviceToken, isNull);

    server.offline = true;
    api.deviceToken = 'ключ';
    await api.logout();
    expect(api.deviceToken, isNull);
  });

  test('ошибка: текст сервера показывается как есть', () async {
    final api = ApiClient(
      baseUrl: 'http://server',
      client: MockClient((_) async =>
          http.Response.bytes(utf8.encode(jsonEncode({'message': 'Вход закрыт — обратитесь к директору'})), 403)),
    );

    expect(
        () => api.login('x', 'y'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Вход закрыт — обратитесь к директору')
            .having((e) => e.status, 'status', 403)));
  });

  test('ошибка без текста: понятная подпись по коду ответа', () async {
    final api = ApiClient(baseUrl: 'http://server', client: MockClient((_) async => http.Response('', 401)));

    expect(() => api.login('x', 'y'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Неверный телефон или пароль')));
  });

  test('нет связи с сервером', () async {
    final api = ApiClient(baseUrl: 'http://server', client: (FakeServer()..offline = true).client);

    expect(
        () => api.login('x', 'y'),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', isNull)
            .having((e) => e.message, 'message', 'Нет связи с сервером')));
  });
}
