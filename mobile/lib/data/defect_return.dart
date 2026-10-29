import 'dart:convert';

/// Возврат негодного товара, принятый экспедитором у магазина из рейса: товар — в машину, долг магазина
/// уменьшается по цене продажи ему в день возврата (считает сервер). Пишется на телефон и уходит на сервер
/// (POST /api/mobile/expeditor/returns). uuid создаёт телефон — повтор не задвоит.
class DefectReturn {
  DefectReturn({
    required this.uuid,
    required this.outletId,
    required this.tripId,
    required this.returnedAt,
    required this.reason,
    required this.items,
    required this.total,
    this.sent = false,
    this.error,
    this.debtAfter,
    this.plan = false,
  });

  final String uuid;
  final int outletId;
  final int tripId;
  final DateTime returnedAt;

  /// EXPIRED, DEFECT или PACKAGING — одна на весь возврат.
  final String reason;

  /// Сколько штук по товарам: id → штук.
  final Map<int, int> items;

  /// На сколько уменьшается долг: сначала — по ценам на телефоне, после отправки — как посчитал сервер.
  int total;

  bool sent;

  /// Сервер не принял — почему.
  String? error;

  /// Долг магазина после возврата — как ответил сервер (минус — аванс).
  int? debtAfter;

  /// Забран по списку, который торговый записал с заказом.
  final bool plan;

  static const reasons = {'DEFECT': 'Брак', 'EXPIRED': 'Просрочка', 'PACKAGING': 'Упаковка'};

  String get reasonLabel => reasons[reason] ?? reason;
  int get qty => items.values.fold(0, (a, b) => a + b);

  /// Для сервера.
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'outletId': outletId,
        'tripId': tripId,
        'returnedAt': returnedAt.toIso8601String().split('.').first,
        'lines': [for (final e in items.entries) {'productId': e.key, 'qty': e.value, 'reason': reason}],
      };

  /// Всё, что нужно хранить на телефоне, — одной строкой JSON.
  String encode() => jsonEncode({
        'uuid': uuid,
        'outletId': outletId,
        'tripId': tripId,
        'returnedAt': returnedAt.toIso8601String(),
        'reason': reason,
        'items': {for (final e in items.entries) '${e.key}': e.value},
        'total': total,
        'sent': sent,
        'error': error,
        'debtAfter': debtAfter,
        'plan': plan,
      });

  factory DefectReturn.decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return DefectReturn(
      uuid: j['uuid'] as String,
      outletId: j['outletId'] as int,
      tripId: j['tripId'] as int,
      returnedAt: DateTime.parse(j['returnedAt'] as String),
      reason: j['reason'] as String,
      items: {for (final e in (j['items'] as Map<String, dynamic>).entries) int.parse(e.key): e.value as int},
      total: j['total'] as int,
      sent: j['sent'] as bool? ?? false,
      error: j['error'] as String?,
      debtAfter: j['debtAfter'] as int?,
      plan: j['plan'] as bool? ?? false,
    );
  }

  DefectReturn copy() => DefectReturn.decode(encode());
}
