import 'dart:convert';

/// Выдача заказа экспедитором: всё, частично или отказ магазина — и деньги, полученные за заказ. Пишется на телефон
/// и уходит на сервер (POST /api/mobile/expeditor/deliveries). uuid создаёт телефон — повтор не задвоит.
class Delivery {
  Delivery({
    required this.uuid,
    required this.orderId,
    required this.tripId,
    required this.outletId,
    required this.deliveredAt,
    this.refuseReason,
    this.items = const {},
    this.total = 0,
    this.cash = 0,
    this.kaspi = 0,
    required this.cashUuid,
    required this.kaspiUuid,
    this.lat,
    this.lng,
    this.sent = false,
    this.error,
    this.statusLabel,
  });

  final String uuid;
  final int orderId;
  final int tripId;
  final int outletId;
  final DateTime deliveredAt;

  /// Магазин отказался — почему; null — выдано.
  final String? refuseReason;

  /// Сколько выдано по товарам (productId → штук), когда выдано не всё; пусто — выдано всё.
  final Map<int, int> items;

  /// На сколько выдано.
  final int total;

  /// Получено наличными и Kaspi.
  final int cash;
  final int kaspi;

  /// uuid оплат — создаются вместе с выдачей и не меняются, чтобы повтор не задвоил деньги.
  final String cashUuid;
  final String kaspiUuid;

  /// Где был телефон.
  final double? lat;
  final double? lng;

  bool sent;

  /// Сервер не принял — почему.
  String? error;

  /// Как назвал сервер: «Доставлен», «Частично», «Отказ магазина».
  String? statusLabel;

  bool get refused => refuseReason != null;
  bool get partial => !refused && items.isNotEmpty;
  int get paid => cash + kaspi;

  /// Остаток, который уходит в долг магазина.
  int get unpaid => refused ? 0 : total - paid;

  /// Для сервера.
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'orderId': orderId,
        'deliveredAt': deliveredAt.toIso8601String().split('.').first,
        'refused': refused,
        'refuseReason': refuseReason,
        'lat': lat,
        'lng': lng,
        'items': [for (final e in items.entries) {'productId': e.key, 'qty': e.value}],
        'payments': [
          if (cash > 0) {'uuid': cashUuid, 'method': 'CASH', 'amount': cash},
          if (kaspi > 0) {'uuid': kaspiUuid, 'method': 'KASPI', 'amount': kaspi},
        ],
      };

  /// Всё, что нужно хранить на телефоне, — одной строкой JSON.
  String encode() => jsonEncode({
        'uuid': uuid,
        'orderId': orderId,
        'tripId': tripId,
        'outletId': outletId,
        'deliveredAt': deliveredAt.toIso8601String(),
        'refuseReason': refuseReason,
        'items': {for (final e in items.entries) '${e.key}': e.value},
        'total': total,
        'cash': cash,
        'kaspi': kaspi,
        'cashUuid': cashUuid,
        'kaspiUuid': kaspiUuid,
        'lat': lat,
        'lng': lng,
        'sent': sent,
        'error': error,
        'statusLabel': statusLabel,
      });

  factory Delivery.decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return Delivery(
      uuid: j['uuid'] as String,
      orderId: j['orderId'] as int,
      tripId: j['tripId'] as int,
      outletId: j['outletId'] as int,
      deliveredAt: DateTime.parse(j['deliveredAt'] as String),
      refuseReason: j['refuseReason'] as String?,
      items: {for (final e in (j['items'] as Map<String, dynamic>).entries) int.parse(e.key): e.value as int},
      total: j['total'] as int,
      cash: j['cash'] as int,
      kaspi: j['kaspi'] as int,
      cashUuid: j['cashUuid'] as String,
      kaspiUuid: j['kaspiUuid'] as String,
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      sent: j['sent'] as bool? ?? false,
      error: j['error'] as String?,
      statusLabel: j['statusLabel'] as String?,
    );
  }

  Delivery copy() => Delivery.decode(encode());
}
