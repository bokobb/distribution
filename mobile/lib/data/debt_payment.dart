import 'dart:convert';

/// Оплата старого долга, принятая экспедитором у магазина из рейса: не за заказ, а в счёт долга. Пишется на телефон
/// и уходит на сервер (POST /api/mobile/expeditor/payments). uuid создаёт телефон — повтор не задвоит.
class DebtPayment {
  DebtPayment({
    required this.uuid,
    required this.outletId,
    required this.tripId,
    required this.method,
    required this.amount,
    required this.paidAt,
    this.sent = false,
    this.error,
    this.debtAfter,
  });

  final String uuid;
  final int outletId;
  final int tripId;

  /// CASH или KASPI.
  final String method;
  final int amount;
  final DateTime paidAt;

  bool sent;

  /// Сервер не принял — почему.
  String? error;

  /// Долг магазина после оплаты — как ответил сервер (минус — аванс).
  int? debtAfter;

  String get methodLabel => method == 'KASPI' ? 'Kaspi' : 'наличными';

  /// Для сервера.
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'outletId': outletId,
        'tripId': tripId,
        'method': method,
        'amount': amount,
        'paidAt': paidAt.toIso8601String().split('.').first,
      };

  /// Всё, что нужно хранить на телефоне, — одной строкой JSON.
  String encode() => jsonEncode(
      {...toJson(), 'paidAt': paidAt.toIso8601String(), 'sent': sent, 'error': error, 'debtAfter': debtAfter});

  factory DebtPayment.decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return DebtPayment(
      uuid: j['uuid'] as String,
      outletId: j['outletId'] as int,
      tripId: j['tripId'] as int,
      method: j['method'] as String,
      amount: j['amount'] as int,
      paidAt: DateTime.parse(j['paidAt'] as String),
      sent: j['sent'] as bool? ?? false,
      error: j['error'] as String?,
      debtAfter: j['debtAfter'] as int?,
    );
  }

  DebtPayment copy() => DebtPayment.decode(encode());
}
