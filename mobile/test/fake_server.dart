import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Сервер для тестов: отвечает как /api/mobile (пароль «пароль», ключ устройства «ключ»); что приходило — в [requests].
class FakeServer {
  FakeServer({this.role = 'AGENT', this.mustChange = false});

  String role;
  bool mustChange;

  /// Ключ устройства действует (не вышли, пароль не сбрасывали).
  bool keyOpen = true;

  /// Сервер недоступен.
  bool offline = false;

  final requests = <http.Request>[];
  String? _jwt;
  int _seq = 0;

  late final client = MockClient((r) async {
    if (offline) throw http.ClientException('Connection refused');
    requests.add(r);
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    final authed = r.headers['Authorization'] == 'Bearer $_jwt' && _jwt != null;
    switch (r.url.path) {
      case '/api/mobile/auth/login':
        if (body['password'] != 'пароль') return _json({'message': 'Неверный телефон или пароль'}, 401);
        if (role == 'OPERATOR') return _json({'message': 'Оператор работает в веб-админке.'}, 403);
        return _json(_tokens(), 200);
      case '/api/mobile/auth/refresh':
        if (!keyOpen || body['deviceToken'] != 'ключ') {
          return _json({'message': 'Вход на этом телефоне закрыт — войдите с паролем'}, 401);
        }
        return _json(_tokens(), 200);
      case '/api/mobile/auth/logout':
        keyOpen = false;
        return http.Response('', 204);
      case '/api/mobile/auth/password':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        if (body['current'] != 'пароль') return _json({'message': 'Текущий пароль неверный'}, 400);
        mustChange = false;
        return _json(_user(), 200);
      case '/api/mobile/me':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        return _json(_user(), 200);
    }
    return http.Response('', 404);
  });

  /// JWT истёк или сервер перезапускался: прежний больше не принимается.
  void expireJwt() => _jwt = null;

  int count(String path) => requests.where((r) => r.url.path == path).length;

  Map<String, dynamic> _user() =>
      {'id': 1, 'name': 'Иван', 'role': role, 'company': 'Своя доставка', 'mustChangePassword': mustChange};

  Map<String, dynamic> _tokens() {
    _jwt = 'jwt-${++_seq}';
    return {'token': _jwt, 'expiresIn': 43200, 'deviceToken': 'ключ', 'user': _user()};
  }

  static http.Response _json(Object body, int status) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});
}
