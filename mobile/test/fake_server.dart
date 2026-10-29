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

  /// Что сервер отдаёт экспедитору: рейс сегодня на две точки (вторая выдана) и рейс на завтра.
  Map<String, dynamic> expeditorData = sampleExpeditorData();

  /// Что пришло на /api/mobile/track.
  final trackEvents = <Map<String, dynamic>>[];
  final trackPoints = <Map<String, dynamic>>[];
  int? lastUnsent;

  /// Визиты по uuid и фото полки к ним — что пришло.
  final visits = <String, Map<String, dynamic>>{};
  final photos = <String, List<int>>{};

  /// Подтверждения выдач по uuid выдачи: тип и байты (подпись PNG или фото накладной JPEG).
  final proofs = <String, (String?, List<int>)>{};

  /// Столько подтверждений «потерять» — сеть пропала посреди отправки.
  int dropProofs = 0;

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

  /// Выдачи по uuid — что пришло; принятая сразу меняет статус заказа в данных экспедитора.
  final deliveries = <String, Map<String, dynamic>>{};

  /// Сервер не принимает выдачи — с этим текстом.
  String? rejectDeliveries;

  /// Оплаты долга по uuid — что пришло; принятая уменьшает долг магазина в данных экспедитора.
  final debtPayments = <String, Map<String, dynamic>>{};

  /// Сервер не принимает оплаты долга — с этим текстом.
  String? rejectDebtPayments;

  /// Возвраты негодного по uuid — что пришло; принятый уменьшает долг магазина по оптовой цене товара.
  final returns = <String, Map<String, dynamic>>{};

  /// Карточки магазинов (/outlets/{id}/card): id → что отдаёт сервер; нет — пустая карточка.
  final cards = <int, Map<String, dynamic>>{1: sampleCard()};

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
    final proof = RegExp(r'^/api/mobile/expeditor/deliveries/([^/]+)/proof$').firstMatch(r.url.path);
    if (proof != null) {
      if (dropProofs > 0) {
        dropProofs--;
        throw http.ClientException('Connection reset');
      }
      if (!authed) return _json({'message': 'Войдите заново'}, 401);
      if (!deliveries.containsKey(proof[1])) return _json({'message': 'Не найдено'}, 404);
      proofs[proof[1]!] = (r.headers['content-type'], r.bodyBytes);
      return http.Response('', 204);
    }
    final card = RegExp(r'^/api/mobile/agent/outlets/(-?\d+)/card$').firstMatch(r.url.path);
    if (card != null) {
      if (!authed) return _json({'message': 'Войдите заново'}, 401);
      return _json(cards[int.parse(card[1]!)] ?? {
        'outletId': int.parse(card[1]!), 'createdOn': '2026-10-28', 'avgOrder': 0, 'orders8w': 0, 'ordered': 0,
        'returned': 0, 'returnReason': null, 'stopped': null, 'stoppedSince': null, 'history': [],
      }, 200);
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
        final back = (body['returns'] as List? ?? const []).fold<int>(0, (a, i) => a + ((i as Map)['qty'] as int));
        return _json({
          'uuid': body['uuid'], 'outletId': body['outletId'], 'number': 'З-281026-$n', 'createdAt': body['createdAt'],
          'deliveryDate': body['deliveryDate'], 'payment': body['payment'],
          'status': needsApproval ? 'NEEDS_APPROVAL' : 'ACCEPTED',
          'statusLabel': needsApproval ? 'Нужно разрешение' : 'Принят',
          'note': needsApproval ? 'Долг сверх лимита — ждёт разрешения оператора' : null,
          'total': qty * 500, 'lines': [], 'returnTotal': back * 500, 'returns': body['returns'] ?? [],
        }, 200);
      case '/api/mobile/agent/outlets':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        if (rejectOutlets != null) return _json({'message': rejectOutlets}, 400);
        return _json(outlets.putIfAbsent(body['uuid'] as String, () => _addOutlet(body)), 200);
      case '/api/mobile/agent/data':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        return _json(agentData, 200);
      case '/api/mobile/expeditor/deliveries':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        if (role != 'EXPEDITOR') return _json({'message': 'Нет доступа'}, 403);
        if (rejectDeliveries != null) return _json({'message': rejectDeliveries}, 400);
        return _json(_deliver(deliveries.putIfAbsent(body['uuid'] as String, () => body)), 200);
      case '/api/mobile/expeditor/payments':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        if (role != 'EXPEDITOR') return _json({'message': 'Нет доступа'}, 403);
        if (rejectDebtPayments != null) return _json({'message': rejectDebtPayments}, 400);
        final uuid = body['uuid'] as String;
        final outlets = [
          for (final t in expeditorData['trips'] as List)
            for (final s in (t as Map)['stops'] as List) (s as Map)['outlet'] as Map<String, dynamic>
        ].where((o) => o['id'] == body['outletId']);
        if (!debtPayments.containsKey(uuid)) {
          debtPayments[uuid] = body;
          _addCash(body['tripId'] as int, body['method'] == 'KASPI' ? 'kaspi' : 'cash', body['amount'] as int);
          _addCash(body['tripId'] as int, 'oldDebt', body['amount'] as int);
          for (final o in outlets) {
            o['debt'] = (o['debt'] as int) - (body['amount'] as int);
          }
        }
        return _json({...body, 'debt': outlets.first['debt']}, 200);
      case '/api/mobile/expeditor/returns':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        if (role != 'EXPEDITOR') return _json({'message': 'Нет доступа'}, 403);
        final uuid = body['uuid'] as String;
        final outlets = [
          for (final t in expeditorData['trips'] as List)
            for (final s in (t as Map)['stops'] as List) (s as Map)['outlet'] as Map<String, dynamic>
        ].where((o) => o['id'] == body['outletId']);
        final total = (body['lines'] as List).fold<int>(0, (a, l) {
          final p = _products.firstWhere((p) => p['id'] == (l as Map)['productId']);
          return a + (l['qty'] as int) * (p['wholesale'] as int);
        });
        if (!returns.containsKey(uuid)) {
          returns[uuid] = body;
          _addCash(body['tripId'] as int, 'returnsQty',
              (body['lines'] as List).fold<int>(0, (a, l) => a + ((l as Map)['qty'] as int)));
          _addCash(body['tripId'] as int, 'returnsTotal', total);
          for (final o in outlets) {
            o['debt'] = (o['debt'] as int) - total;
          }
        }
        return _json({'uuid': uuid, 'outletId': body['outletId'], 'total': total, 'debt': outlets.first['debt'], 'lines': []}, 200);
      case '/api/mobile/expeditor/data':
        if (!authed) return _json({'message': 'Войдите заново'}, 401);
        if (role != 'EXPEDITOR') return _json({'message': 'Нет доступа'}, 403);
        // как на сервере: касса рейса посчитана на сейчас — что ушло с телефона, уже в ней
        if (requests.where((r) => r.url.path == '/api/mobile/expeditor/data').length > 1) {
          expeditorData['syncedAt'] = DateTime.now().toIso8601String();
        }
        return _json(expeditorData, 200);
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

  /// Выдача — как сервер: статус и суммы заказа в данных экспедитора.
  Map<String, dynamic> _deliver(Map<String, dynamic> body) {
    final trip = (expeditorData['trips'] as List).cast<Map<String, dynamic>>().firstWhere(
        (t) => (t['stops'] as List).any((s) => ((s as Map)['order'] as Map)['id'] == body['orderId']));
    final order = [for (final s in trip['stops'] as List) (s as Map)['order'] as Map<String, dynamic>]
        .firstWhere((o) => o['id'] == body['orderId']);
    for (final p in (body['payments'] as List).cast<Map<String, dynamic>>()) {
      _addCash(trip['id'] as int, p['method'] == 'KASPI' ? 'kaspi' : 'cash', p['amount'] as int);
    }
    final items = {for (final i in body['items'] as List) (i as Map)['productId'] as int: i['qty'] as int};
    final refused = body['refused'] as bool;
    var total = 0;
    for (final l in (order['lines'] as List).cast<Map<String, dynamic>>()) {
      final qty = refused ? 0 : items.isEmpty ? l['qty'] as int : items[l['productId']] ?? 0;
      l['delivered'] = qty;
      total += qty * (l['price'] as int);
    }
    final paid = (body['payments'] as List).fold<int>(0, (a, p) => a + ((p as Map)['amount'] as int));
    final (status, label) =
        refused ? ('REFUSED', 'Отказ магазина') : items.isEmpty ? ('DELIVERED', 'Доставлен') : ('PARTIAL', 'Частично');
    order
      ..['status'] = status
      ..['statusLabel'] = label
      ..['paid'] = paid;
    return {'uuid': body['uuid'], 'orderId': order['id'], 'status': status, 'statusLabel': label, 'total': total, 'paid': paid};
  }

  /// Касса рейса — как на сервере.
  void _addCash(int tripId, String key, int amount) {
    final trip = (expeditorData['trips'] as List).cast<Map<String, dynamic>>().firstWhere((t) => t['id'] == tripId);
    final cash = trip['cash'] as Map<String, dynamic>;
    cash[key] = (cash[key] as int) + amount;
  }

  /// JWT истёк или сервер перезапускался: прежний больше не принимается.
  void expireJwt() => _jwt = null;

  int count(String path) => requests.where((r) => r.url.path == path).length;

  Map<String, dynamic> _user() =>
      {'id': 1, 'name': 'Иван', 'role': role, 'company': 'Своя доставка', 'phone': '+77010000101', 'mustChangePassword': mustChange};

  Map<String, dynamic> _tokens() {
    _jwt = 'jwt-${++_seq}';
    return {'token': _jwt, 'expiresIn': 43200, 'deviceToken': 'ключ', 'user': _user()};
  }

  static http.Response _json(Object body, int status) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});
}

Map<String, dynamic> _noCash() => {'cash': 0, 'kaspi': 0, 'oldDebt': 0, 'returnsQty': 0, 'returnsTotal': 0};

String _day(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

Map<String, dynamic> _outlet(int id, String name, {int debt = 0, int overdue = 0}) => {
      'id': id, 'uuid': '00000000-0000-0000-0000-00000000000$id', 'name': name, 'legal': 'ИП $name', 'owner': null,
      'phone': '+77010000000', 'phone2': null, 'address': 'ул. Байтурсынова, $id', 'landmark': null,
      'lat': 42.3, 'lng': 69.6, 'priceKind': 'WHOLESALE', 'creditLimit': 100000, 'paymentDays': 7,
      'status': 'ACTIVE', 'debt': debt, 'overdue': overdue, 'lastPaymentDate': null, 'lastPaymentSum': 0,
    };

final _products = [
  {'id': 1, 'name': 'Печенье овсяное', 'category': 'Печенье', 'unit': 'шт', 'perBox': 12, 'barcode': null,
    'wholesale': 500, 'retail': 600},
  {'id': 2, 'name': 'Вафли сливочные', 'category': 'Вафли', 'unit': 'шт', 'perBox': 20, 'barcode': '4870001',
    'wholesale': 300, 'retail': 350},
  {'id': 3, 'name': 'Торт «Наполеон»', 'category': 'Торты', 'unit': 'шт', 'perBox': 1, 'barcode': null,
    'wholesale': 0, 'retail': 0},
];

/// Рейс сегодня: «Арай» — 24 печенья и 5 вафель за наличные (13 500 ₸), «Береке» — выдан, в долг; на завтра —
/// «Сайрам» по Kaspi.
Map<String, dynamic> sampleExpeditorData({DateTime? now}) {
  final t = now ?? DateTime.now();
  Map<String, dynamic> line(int id, String name, int perBox, int qty, int price, {int? delivered}) => {
        'productId': id, 'name': name, 'unit': 'шт', 'perBox': perBox, 'qty': qty, 'price': price, 'delivered': delivered,
      };
  Map<String, dynamic> order(int id, String number, String payment, List<Map<String, dynamic>> lines,
          {String status = 'IN_TRIP', String label = 'В рейсе', int paid = 0}) =>
      {
        'id': id, 'uuid': '00000000-0000-0000-0000-0000000000$id', 'number': number, 'agent': 'Айгерим',
        'deliveryDate': _day(t), 'payment': payment, 'comment': null, 'status': status, 'statusLabel': label,
        'total': lines.fold<int>(0, (a, l) => a + (l['qty'] as int) * (l['price'] as int)), 'paid': paid, 'lines': lines,
      };
  return {
    'date': _day(t),
    'syncedAt': '${_day(t)}T07:30:00',
    'company': {'name': 'Своя доставка', 'phone': '+7 700 000 01 00'},
    'settings': {'acceptKaspi': true, 'allowCredit': true, 'gpsInterval': 5},
    'products': _products,
    'trips': [
      {
        'id': 1, 'number': 'Р-281026-1', 'date': _day(t), 'status': 'ON_ROAD', 'statusLabel': 'В пути',
        'vehicle': '245 AKS 02', 'cash': _noCash(),
        'stops': [
          {
            'position': 0,
            'outlet': _outlet(1, 'Магазин «Арай»', debt: 45000, overdue: 12000),
            'order': {
              ...order(11, 'З-271026-1', 'CASH',
                  [line(1, 'Печенье овсяное', 12, 24, 500), line(2, 'Вафли сливочные', 20, 5, 300)]),
              'comment': 'после обеда',
            },
          },
          {
            'position': 1,
            'outlet': _outlet(2, 'Магазин «Береке»'),
            'order': order(12, 'З-271026-2', 'CREDIT', [line(1, 'Печенье овсяное', 12, 10, 500, delivered: 10)],
                status: 'DELIVERED', label: 'Доставлен'),
          },
        ],
      },
      {
        'id': 2, 'number': 'Р-291026-1', 'date': _day(t.add(const Duration(days: 1))), 'status': 'ON_ROAD',
        'statusLabel': 'В пути', 'vehicle': '245 AKS 02', 'cash': _noCash(),
        'stops': [
          {
            'position': 0,
            'outlet': _outlet(3, 'Магазин «Сайрам»'),
            'order': order(13, 'З-281026-5', 'KASPI', [line(2, 'Вафли сливочные', 20, 40, 300)]),
          },
        ],
      },
    ],
  };
}

Map<String, dynamic> sampleAgentData({DateTime? now}) {
  final t = now ?? DateTime.now();
  String d(DateTime x) => _day(x);
  Map<String, dynamic> outlet(int id, String name, {int debt = 0, int overdue = 0}) =>
      _outlet(id, name, debt: debt, overdue: overdue);
  return {
    'date': d(t),
    'syncedAt': '${d(t)}T09:15:00',
    'settings': {
      'visitRadius': 200, 'shelfPhotoRequired': false, 'refuseReasonRequired': true, 'deliveryDays': 1,
      'allowCredit': true, 'approvalOverLimit': true, 'agentDiscount': false, 'acceptKaspi': true, 'gpsInterval': 5,
    },
    'products': _products,
    'routes': [
      {'id': 1, 'name': 'Центр', 'region': 'Шымкент', 'days': [t.weekday], 'outlets': [2, 1]},
      {'id': 2, 'name': 'Сайрам', 'region': 'Сайрам', 'days': [t.weekday % 7 + 1], 'outlets': [3]},
    ],
    'outlets': [
      outlet(1, 'Магазин «Арай»', debt: 45000, overdue: 12000),
      outlet(2, 'Магазин «Береке»'),
      outlet(3, 'Магазин «Сайрам»'),
    ],
    'others': [
      {'id': 10, 'name': 'Магазин «Сосед»', 'address': 'ул. Абая, 1', 'landmark': null, 'lat': 42.31, 'lng': 69.61,
        'region': 'Шымкент', 'owner': 'Гульнара М.', 'priceKind': 'RETAIL', 'status': 'ACTIVE'},
      {'id': 11, 'name': 'Магазин «Ак жол»', 'address': null, 'landmark': 'у трассы', 'lat': 42.29, 'lng': 69.75,
        'region': 'Сайрам', 'owner': null, 'priceKind': 'WHOLESALE', 'status': 'ACTIVE'},
      {'id': 12, 'name': 'Магазин «Без точки»', 'address': 'ул. Кунаева, 40', 'landmark': null, 'lat': null, 'lng': null,
        'region': null, 'owner': null, 'priceKind': 'WHOLESALE', 'status': 'PENDING'},
    ],
    'lastOrders': [
      {'outletId': 1, 'date': '2026-10-21', 'items': [{'productId': 1, 'qty': 24}, {'productId': 2, 'qty': 40}]},
    ],
    'stats': [
      {'outletId': 1, 'lastVisit': d(t.subtract(const Duration(days: 1))), 'avgOrder': 30400, 'createdOn': '2025-03-12'},
      {'outletId': 2, 'lastVisit': d(t.subtract(const Duration(days: 10))), 'avgOrder': 0, 'createdOn': '2025-05-02'},
      {'outletId': 3, 'lastVisit': null, 'avgOrder': 0, 'createdOn': '2025-06-20'},
      {'outletId': 10, 'lastVisit': d(t.subtract(const Duration(days: 2))), 'avgOrder': 24600, 'createdOn': '2025-01-15'},
      {'outletId': 11, 'lastVisit': d(t.subtract(const Duration(days: 8))), 'avgOrder': 13900, 'createdOn': '2025-02-01'},
      {'outletId': 12, 'lastVisit': null, 'avgOrder': 0, 'createdOn': '2026-10-24'},
    ],
    // вчера: «Арай» доставлен утром, «Береке» в долг — ещё нет
    'previousDate': d(t.subtract(const Duration(days: 1))),
    'previousOrders': [
      _order(31, 1, t.subtract(const Duration(days: 1)), 'CASH', [(1, 24, 500), (2, 10, 300)],
          status: 'DELIVERED', label: 'Доставлен', deliveredAt: '${d(t)}T09:12:00'),
      _order(32, 2, t.subtract(const Duration(days: 1)), 'CREDIT', [(1, 10, 500)]),
    ],
  };
}

/// Заказ агента, как его отдаёт сервер: строки (товар, штук, цена).
Map<String, dynamic> _order(int id, int outletId, DateTime day, String payment, List<(int, int, int)> lines,
        {String status = 'ACCEPTED', String label = 'Принят', String? deliveredAt}) =>
    {
      'uuid': '00000000-0000-0000-0000-0000000000$id', 'outletId': outletId, 'number': 'З-$id',
      'createdAt': '${_day(day)}T10:${id % 60}:00', 'deliveryDate': _day(day.add(const Duration(days: 1))),
      'payment': payment, 'status': status, 'statusLabel': label, 'note': null,
      'total': lines.fold<int>(0, (a, l) => a + l.$2 * l.$3),
      'lines': [for (final l in lines) {'productId': l.$1, 'qty': l.$2, 'price': l.$3, 'sum': l.$2 * l.$3}],
      'returnTotal': 0, 'returns': [], 'deliveredAt': deliveredAt,
    };

/// Карточка «Арай»: средний заказ, раз в неделю, возвраты 3 %, перестал брать вафли; заказ с возвратом и визит без заказа.
Map<String, dynamic> sampleCard() => {
      'outletId': 1, 'createdOn': '2025-03-12', 'avgOrder': 30400, 'orders8w': 8, 'ordered': 400000,
      'returned': 12000, 'returnReason': 'EXPIRED', 'stopped': 'Вафли сливочные', 'stoppedSince': '2026-10-07',
      'history': [
        {'at': '2026-10-21T10:15:00', 'kind': 'ORDER', 'orderTotal': 31680, 'returnTotal': 1240,
          'returnReason': 'PACKAGING', 'status': 'DELIVERED', 'statusLabel': 'Доставлен', 'reason': null},
        {'at': '2026-10-14T11:00:00', 'kind': 'ORDER', 'orderTotal': 29400, 'returnTotal': 0, 'returnReason': null,
          'status': 'DELIVERED', 'statusLabel': 'Доставлен', 'reason': null},
        {'at': '2026-09-30T12:40:00', 'kind': 'NO_ORDER', 'orderTotal': 0, 'returnTotal': 0, 'returnReason': null,
          'status': null, 'statusLabel': null, 'reason': 'Товар ещё есть'},
      ],
    };
