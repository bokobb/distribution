import 'dart:convert';

import 'package:distribution_mobile/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  test('вход: сотрудник из ответа сервера', () async {
    late http.Request sent;
    final api = ApiClient(
      baseUrl: 'http://server',
      client: MockClient((r) async {
        sent = r;
        return jsonResponse({
          'user': {'id': 7, 'name': 'Агент Шымкент', 'role': 'AGENT', 'company': 'Своя доставка'}
        }, 200);
      }),
    );

    final s = await api.login('87010000101', 'секрет');

    expect(sent.url.toString(), 'http://server/api/mobile/auth/login');
    expect(jsonDecode(sent.body), {'login': '87010000101', 'password': 'секрет'});
    expect(s.userId, 7);
    expect(s.name, 'Агент Шымкент');
    expect(s.isAgent, isTrue);
    expect(s.company, 'Своя доставка');
  });

  test('ошибка: текст сервера показывается как есть', () async {
    final api = ApiClient(
      baseUrl: 'http://server',
      client: MockClient((_) async => jsonResponse({'message': 'Сотрудник отключён'}, 403)),
    );

    expect(() => api.login('x', 'y'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Сотрудник отключён').having((e) => e.status, 'status', 403)));
  });

  test('ошибка без текста: понятная подпись по коду ответа', () async {
    final api = ApiClient(baseUrl: 'http://server', client: MockClient((_) async => http.Response('', 401)));

    expect(() => api.login('x', 'y'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Неверный телефон или пароль')));
  });

  test('нет связи с сервером', () async {
    final api = ApiClient(
      baseUrl: 'http://server',
      client: MockClient((_) async => throw http.ClientException('Connection refused')),
    );

    expect(() => api.login('x', 'y'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', isNull).having((e) => e.message, 'message', 'Нет связи с сервером')));
  });
}
