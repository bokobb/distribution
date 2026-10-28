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

  /// Что сервер отдаёт агенту: сегодня маршрут «Центр» из двух магазинов, у второго долг с просрочкой.
  Map<String, dynamic> agentData = sampleAgentData();

  /// Что пришло на /api/mobile/track.
  final trackEvents = <Map<String, dynamic>>[];
  final trackPoints = <Map<String, dynamic>>[];
  int? lastUnsent;

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
      case '/api/mobile/track':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        trackEvents.addAll((body['events'] as List).cast<Map<String, dynamic>>());
        trackPoints.addAll((body['points'] as List).cast<Map<String, dynamic>>());
        lastUnsent = body['unsent'] as int?;
        return _json({'events': 0, 'points': 0, 'duplicates': 0, 'outsideDay': 0, 'invalid': 0}, 200);
      case '/api/mobile/agent/data':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        return _json(agentData, 200);
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

Map<String, dynamic> sampleAgentData({DateTime? now}) {
  final t = now ?? DateTime.now();
  String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  Map<String, dynamic> outlet(int id, String name, {int debt = 0, int overdue = 0}) => {
        'id': id, 'uuid': '00000000-0000-0000-0000-00000000000$id', 'name': name, 'legal': 'ИП $name', 'owner': null,
        'phone': '+77010000000', 'phone2': null, 'address': 'ул. Байтурсынова, $id', 'landmark': null,
        'lat': 42.3, 'lng': 69.6, 'priceKind': 'WHOLESALE', 'creditLimit': 100000, 'paymentDays': 7,
        'status': 'ACTIVE', 'debt': debt, 'overdue': overdue, 'lastPaymentDate': null, 'lastPaymentSum': 0,
      };
  return {
    'date': d(t),
    'syncedAt': '${d(t)}T09:15:00',
    'settings': {
      'visitRadius': 200, 'shelfPhotoRequired': false, 'refuseReasonRequired': true, 'deliveryDays': 1,
      'allowCredit': true, 'approvalOverLimit': true, 'agentDiscount': false, 'acceptKaspi': true, 'gpsInterval': 5,
    },
    'products': [
      {'id': 1, 'name': 'Печенье овсяное', 'category': 'Печенье', 'unit': 'шт', 'perBox': 12, 'barcode': null,
        'wholesale': 500, 'retail': 600},
    ],
    'routes': [
      {'id': 1, 'name': 'Центр', 'region': 'Шымкент', 'days': [t.weekday], 'outlets': [2, 1]},
      {'id': 2, 'name': 'Сайрам', 'region': 'Сайрам', 'days': [t.weekday % 7 + 1], 'outlets': [3]},
    ],
    'outlets': [
      outlet(1, 'Магазин «Арай»', debt: 45000, overdue: 12000),
      outlet(2, 'Магазин «Береке»'),
      outlet(3, 'Магазин «Сайрам»'),
    ],
  };
}
