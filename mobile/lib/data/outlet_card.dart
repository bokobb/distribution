/// Карточка магазина с сервера (/api/mobile/agent/outlets/{id}/card): что он берёт за 90 дней и история визитов с
/// заказами и возвратами. Долг — в данных агента (только у своих), сюда не входит. Берётся при открытии карточки,
/// на телефоне не хранится.
class OutletCard {
  const OutletCard({
    required this.createdOn,
    required this.avgOrder,
    required this.orders8w,
    required this.ordered,
    required this.returned,
    this.stopped,
    this.stoppedSince,
    required this.history,
  });

  final DateTime createdOn;

  /// Средний заказ, ₸; заказов за 8 недель.
  final int avgOrder;
  final int orders8w;

  /// Заказано и возвращено за 90 дней, ₸.
  final int ordered;
  final int returned;

  /// Товар, который магазин брал, но перестал, и когда брал последний раз.
  final String? stopped;
  final DateTime? stoppedSince;

  /// Новые сверху.
  final List<HistoryItem> history;

  /// Сколько раз заказывает: «раз в неделю», «2 раза в неделю», «раз в 2 недели», «раз в месяц».
  String get frequency {
    final perWeek = orders8w / 8;
    if (orders8w == 0) return 'за 8 недель заказов не было';
    if (perWeek >= 1.5) {
      final n = perWeek.round();
      return '$n ${n < 5 ? 'раза' : 'раз'} в неделю';
    }
    if (perWeek >= 0.75) return 'раз в неделю';
    if (perWeek >= 0.375) return 'раз в 2 недели';
    return 'раз в месяц';
  }

  /// Доля возвратов от заказов, %; заказов не было — null.
  int? get returnShare => ordered == 0 ? null : (returned * 100 / ordered).round();

  factory OutletCard.fromJson(Map<String, dynamic> j) => OutletCard(
        createdOn: DateTime.parse(j['createdOn'] as String),
        avgOrder: j['avgOrder'] as int,
        orders8w: j['orders8w'] as int,
        ordered: j['ordered'] as int,
        returned: j['returned'] as int,
        stopped: j['stopped'] as String?,
        stoppedSince: j['stoppedSince'] == null ? null : DateTime.parse(j['stoppedSince'] as String),
        history: [for (final h in j['history'] as List) HistoryItem.fromJson(h as Map<String, dynamic>)],
      );
}

/// Визит или заказ в истории магазина: заказ — сумма, возврат (что забрал экспедитор, а пока не забрал — что
/// записал торговый) и статус; без заказа — причина.
class HistoryItem {
  const HistoryItem({
    required this.at,
    required this.order,
    this.orderTotal = 0,
    this.returnTotal = 0,
    this.status,
    this.statusLabel,
    this.reason,
  });

  final DateTime at;
  final bool order;
  final int orderTotal;
  final int returnTotal;
  final String? status;
  final String? statusLabel;
  final String? reason;

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
        at: DateTime.parse(j['at'] as String),
        order: j['kind'] == 'ORDER',
        orderTotal: j['orderTotal'] as int,
        returnTotal: j['returnTotal'] as int,
        status: j['status'] as String?,
        statusLabel: j['statusLabel'] as String?,
        reason: j['reason'] as String?,
      );
}
