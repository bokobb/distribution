import 'dart:convert';

/// Заказ агента из магазина. Собирается во время визита, пишется на телефон и уходит на сервер
/// (POST /api/mobile/agent/orders); uuid создаёт телефон — повтор не задвоит. Цены и итог окончательно
/// считает сервер по прайсу магазина на день заказа: после отправки здесь номер, статус и итог сервера.
/// С заказом может быть возврат негодного товара ([returns]): экспедитор заберёт его при доставке, к оплате —
/// заказ минус возврат.
class Order {
  Order({
    required this.uuid,
    this.visitUuid,
    required this.outletId,
    required this.createdAt,
    required this.deliveryDate,
    required this.payment,
    this.comment,
    required this.items,
    required this.total,
    this.returns = const [],
    this.returnTotal = 0,
    this.sent = false,
    this.error,
    this.number,
    this.status,
    this.statusLabel,
    this.note,
    this.deliveredAt,
  });

  final String uuid;
  final String? visitUuid;

  /// Как у визита: у нового магазина до отправки — номер с телефона.
  int outletId;
  final DateTime createdAt;

  /// День доставки (без времени).
  final DateTime deliveryDate;

  /// CASH, KASPI или CREDIT.
  final String payment;
  final String? comment;

  /// id товара → штук.
  final Map<int, int> items;

  /// Итог, ₸: до отправки — по ценам на телефоне, после — сервера.
  int total;

  /// Возврат, который экспедитор заберёт при доставке, и сколько за него вычтется (как [total]).
  final List<ReturnItem> returns;
  int returnTotal;
  bool sent;

  /// Сервер не принял — почему; такой заказ больше не отправляется.
  String? error;

  /// С сервера: номер, статус (ACCEPTED, NEEDS_APPROVAL, …), его подпись и пояснение.
  String? number;
  String? status;
  String? statusLabel;
  String? note;

  /// С сервера: когда экспедитор отдал товар; не отдал — null.
  DateTime? deliveredAt;

  static const paymentLabels = {'CASH': 'Наличные', 'KASPI': 'Kaspi', 'CREDIT': 'В долг'};

  int get qty => items.values.fold(0, (a, b) => a + b);

  /// К оплате при доставке: заказ минус возврат.
  int get toPay => total - returnTotal;

  Order copy() => Order(
        uuid: uuid,
        visitUuid: visitUuid,
        outletId: outletId,
        createdAt: createdAt,
        deliveryDate: deliveryDate,
        payment: payment,
        comment: comment,
        items: {...items},
        total: total,
        returns: returns,
        returnTotal: returnTotal,
        sent: sent,
        error: error,
        number: number,
        status: status,
        statusLabel: statusLabel,
        note: note,
        deliveredAt: deliveredAt,
      );

  /// Для сервера.
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'visitUuid': visitUuid,
        'outletId': outletId,
        'createdAt': createdAt.toIso8601String().split('.').first,
        'deliveryDate': _day(deliveryDate),
        'payment': payment,
        'comment': comment,
        'items': [for (final e in items.entries) {'productId': e.key, 'qty': e.value}],
        'returns': [for (final r in returns) r.toJson()],
      };

  /// Ответ сервера на отправку или заказ за сегодня из данных агента.
  void takeServer(Map<String, dynamic> j) {
    sent = true;
    number = j['number'] as String?;
    status = j['status'] as String?;
    statusLabel = j['statusLabel'] as String?;
    note = j['note'] as String?;
    final at = j['deliveredAt'] as String?;
    deliveredAt = at == null ? null : DateTime.parse(at);
    total = (j['total'] as num?)?.toInt() ?? total;
    returnTotal = (j['returnTotal'] as num?)?.toInt() ?? returnTotal;
  }

  factory Order.fromServer(Map<String, dynamic> j) => Order(
        uuid: j['uuid'] as String,
        outletId: j['outletId'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
        deliveryDate: DateTime.parse(j['deliveryDate'] as String),
        payment: j['payment'] as String,
        items: {for (final l in j['lines'] as List? ?? const []) (l as Map)['productId'] as int: l['qty'] as int},
        total: (j['total'] as num).toInt(),
        returns: [for (final r in j['returns'] as List? ?? const []) ReturnItem.fromJson(r as Map<String, dynamic>)],
      )..takeServer(j);

  /// Строки для базы на телефоне.
  String itemsJson() => encodeItems(items);

  static String encodeItems(Map<int, int> items) => jsonEncode({for (final e in items.entries) '${e.key}': e.value});

  static Map<int, int> parseItems(String json) =>
      {for (final e in (jsonDecode(json) as Map<String, dynamic>).entries) int.parse(e.key): e.value as int};

  String returnsJson() => encodeReturns(returns);

  static String encodeReturns(List<ReturnItem> returns) => jsonEncode([for (final r in returns) r.toJson()]);

  static List<ReturnItem> parseReturns(String? json) => json == null
      ? const []
      : [for (final r in jsonDecode(json) as List) ReturnItem.fromJson(r as Map<String, dynamic>)];

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Строка возврата, который торговый записал с заказом: магазин отдаёт негодный товар, экспедитор заберёт его при
/// доставке. Долг уменьшится, когда экспедитор запишет, сколько забрал.
class ReturnItem {
  const ReturnItem({required this.productId, required this.qty, required this.reason});

  final int productId;
  final int qty;

  /// EXPIRED, DEFECT или PACKAGING.
  final String reason;

  static const reasons = {'EXPIRED': 'Срок годности', 'DEFECT': 'Брак', 'PACKAGING': 'Упаковка'};

  String get reasonLabel => reasons[reason] ?? reason;

  Map<String, dynamic> toJson() => {'productId': productId, 'qty': qty, 'reason': reason};

  factory ReturnItem.fromJson(Map<String, dynamic> j) =>
      ReturnItem(productId: j['productId'] as int, qty: j['qty'] as int, reason: j['reason'] as String);
}
