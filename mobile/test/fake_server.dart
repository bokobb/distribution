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

  /// Визиты по uuid и фото полки к ним — что пришло.
  final visits = <String, Map<String, dynamic>>{};
  final photos = <String, List<int>>{};

  /// Сервер не принимает визиты (неверные данные) — с этим текстом.
  String? rejectVisits;

  /// Заказы по uuid — что пришло; новые заказы ждут разрешения (долг сверх лимита).
  final orders = <String, Map<String, dynamic>>{};
  bool needsApproval = false;

  /// Новые магазины по uuid и фото фасада — что пришло; принятый сразу попадает в данные агента «на проверке».
  final outlets = <String, Map<String, dynamic>>{};
  final facades = <String, List<int>>{};

  /// Сервер не принимает новые магазины — с этим текстом.
  String? rejectOutlets;

  final requests = <http.Request>[];
  String? _jwt;
  int _seq = 0;

  late final client = MockClient((r) async {
    if (offline) throw http.ClientException('Connection refused');
    requests.add(r);
    final authed = r.headers['Authorization'] == 'Bearer $_jwt' && _jwt != null;
    final photo = RegExp(r'^/api/mobile/agent/visits/([^/]+)/photo$').firstMatch(r.url.path);
    if (photo != null) {
      if (!authed) return _json({'message': 'Войдите заново'}, 401);
      if (!visits.containsKey(photo[1])) return _json({'message': 'Не найдено'}, 404);
      photos[photo[1]!] = r.bodyBytes;
      return http.Response('', 204);
    }
    final facade = RegExp(r'^/api/mobile/agent/outlets/([^/]+)/photo$').firstMatch(r.url.path);
    if (facade != null) {
      if (!authed) return _json({'message': 'Войдите заново'}, 401);
      if (!outlets.containsKey(facade[1])) return _json({'message': 'Не найдено'}, 404);
      facades[facade[1]!] = r.bodyBytes;
      return http.Response('', 204);
    }
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
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
      case '/api/mobile/agent/visits':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        if (rejectVisits != null) return _json({'message': rejectVisits}, 400);
        visits.putIfAbsent(body['uuid'] as String, () => body);
        return _json({...body, 'distance': null, 'photo': photos.containsKey(body['uuid'])}, 200);
      case '/api/mobile/agent/orders':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        orders.putIfAbsent(body['uuid'] as String, () => body);
        final n = orders.keys.toList().indexOf(body['uuid'] as String) + 1;
        final qty = (body['items'] as List).fold<int>(0, (a, i) => a + ((i as Map)['qty'] as int));
        return _json({
          'uuid': body['uuid'], 'outletId': body['outletId'], 'number': 'З-281026-$n', 'createdAt': body['createdAt'],
          'deliveryDate': body['deliveryDate'], 'payment': body['payment'],
          'status': needsApproval ? 'NEEDS_APPROVAL' : 'ACCEPTED',
          'statusLabel': needsApproval ? 'Нужно разрешение' : 'Принят',
          'note': needsApproval ? 'Долг сверх лимита — ждёт разрешения оператора' : null,
          'total': qty * 500, 'lines': [],
        }, 200);
      case '/api/mobile/agent/outlets':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        if (rejectOutlets != null) return _json({'message': rejectOutlets}, 400);
        return _json(outlets.putIfAbsent(body['uuid'] as String, () => _addOutlet(body)), 200);
      case '/api/mobile/agent/data':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        return _json(agentData, 200);
    }
    return http.Response('', 404);
  });

  /// Магазин «на проверке» в конец маршрута агента — как сервер.
  Map<String, dynamic> _addOutlet(Map<String, dynamic> body) {
    final all = agentData['outlets'] as List;
    final routes = (agentData['routes'] as List).cast<Map<String, dynamic>>();
    final id = 100 + outlets.length;
    final o = {
      ...body, 'id': id, 'creditLimit': 0, 'paymentDays': 0, 'status': 'PENDING', 'debt': 0, 'overdue': 0,
      'lastPaymentDate': null, 'lastPaymentSum': 0,
    };
    all.add(o);
    final route = routes.firstWhere((r) => r['id'] == body['routeId'], orElse: () => routes.first);
    route['outlets'] = [...route['outlets'] as List, id];
    return o;
  }

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
      {'id': 2, 'name': 'Вафли сливочные', 'category': 'Вафли', 'unit': 'шт', 'perBox': 20, 'barcode': '4870001',
        'wholesale': 300, 'retail': 350},
      {'id': 3, 'name': 'Торт «Наполеон»', 'category': 'Торты', 'unit': 'шт', 'perBox': 1, 'barcode': null,
        'wholesale': 0, 'retail': 0},
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
