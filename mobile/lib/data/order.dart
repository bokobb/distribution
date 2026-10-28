import 'dart:convert';

/// Заказ агента из магазина. Собирается во время визита, пишется на телефон и уходит на сервер
/// (POST /api/mobile/agent/orders); uuid создаёт телефон — повтор не задвоит. Цены и итог окончательно
/// считает сервер по прайсу магазина на день заказа: после отправки здесь номер, статус и итог сервера.
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
    this.sent = false,
    this.error,
    this.number,
    this.status,
    this.statusLabel,
    this.note,
  });

  final String uuid;
  final String? visitUuid;
  final int outletId;
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
  bool sent;

  /// Сервер не принял — почему; такой заказ больше не отправляется.
  String? error;

  /// С сервера: номер, статус (ACCEPTED, NEEDS_APPROVAL, …), его подпись и пояснение.
  String? number;
  String? status;
  String? statusLabel;
  String? note;

  static const paymentLabels = {'CASH': 'Наличные', 'KASPI': 'Kaspi', 'CREDIT': 'В долг'};

  int get qty => items.values.fold(0, (a, b) => a + b);

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
        sent: sent,
        error: error,
        number: number,
        status: status,
        statusLabel: statusLabel,
        note: note,
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
      };

  /// Ответ сервера на отправку или заказ за сегодня из данных агента.
  void takeServer(Map<String, dynamic> j) {
    sent = true;
    number = j['number'] as String?;
    status = j['status'] as String?;
    statusLabel = j['statusLabel'] as String?;
    note = j['note'] as String?;
    total = (j['total'] as num?)?.toInt() ?? total;
  }

  factory Order.fromServer(Map<String, dynamic> j) => Order(
        uuid: j['uuid'] as String,
        outletId: j['outletId'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
        deliveryDate: DateTime.parse(j['deliveryDate'] as String),
        payment: j['payment'] as String,
        items: {for (final l in j['lines'] as List? ?? const []) (l as Map)['productId'] as int: l['qty'] as int},
        total: (j['total'] as num).toInt(),
      )..takeServer(j);

  /// Строки для базы на телефоне.
  String itemsJson() => encodeItems(items);

  static String encodeItems(Map<int, int> items) => jsonEncode({for (final e in items.entries) '${e.key}': e.value});

  static Map<int, int> parseItems(String json) =>
      {for (final e in (jsonDecode(json) as Map<String, dynamic>).entries) int.parse(e.key): e.value as int};

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
