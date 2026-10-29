import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../data/visit.dart';
import '../format.dart';
import '../geo.dart';
import '../location.dart';
import '../visits.dart';
import '../widgets/layout.dart';

/// Как магазин отмечен на карте: обычный, был сегодня (зелёный), просрочка у своего (янтарный), новый на проверке
/// (белый с рамкой).
enum ShopKind { regular, today, overdue, fresh }

/// Что торговый видит о магазине на карте, в списке и карточке: расстояние, отметка, «не был N дней», плашки. Долги —
/// только у своих магазинов.
class ShopFacts {
  ShopFacts({required this.data, required this.visits, this.fix, DateTime? now}) : now = now ?? DateTime.now();

  final AgentData data;
  final VisitBook visits;

  /// Где торговый сейчас; GPS не ответил — null, расстояний нет.
  final Fix? fix;
  final DateTime now;

  /// «Не был 7+ дней».
  static const staleDays = 7;

  int? meters(Outlet o) {
    final f = fix;
    if (f == null || o.lat == null || o.lng == null) return null;
    return metersBetween(f.lat, f.lng, o.lat!, o.lng!);
  }

  /// Торговый у магазина — в радиусе визита с поправкой на точность GPS.
  bool here(Outlet o) {
    final m = meters(o);
    if (m == null) return false;
    return m - (fix?.accuracy ?? 0).clamp(0, VisitBook.accuracyAllowance) <= data.settings.visitRadius;
  }

  /// Законченный сегодня визит в магазин.
  Visit? visitToday(Outlet o) {
    final v = visits.lastAt(o.id);
    return v != null && !v.open ? v : null;
  }

  ShopKind kind(Outlet o) {
    if (visitToday(o) != null) return ShopKind.today;
    if (o.pending) return ShopKind.fresh;
    if (o.mine && o.overdue > 0) return ShopKind.overdue;
    return ShopKind.regular;
  }

  DateTime get _today => DateUtils.dateOnly(now);

  /// Дней с последнего визита любого торгового (0 — сегодня); не были ни разу — null.
  int? daysAway(Outlet o) {
    if (visitToday(o) != null) return 0;
    final last = data.stats[o.id]?.lastVisit;
    return last == null ? null : _today.difference(last).inDays;
  }

  /// Не были неделю и больше; не были ни разу — если магазин в базе уже неделю.
  bool stale(Outlet o) {
    if (o.pending) return false;
    final days = daysAway(o);
    if (days != null) return days >= staleDays;
    final created = data.stats[o.id]?.createdOn;
    return created == null || _today.difference(created).inDays >= staleDays;
  }

  /// «Был вчера», «Был 3 дня назад», «Не был 10 дней»; не были — null.
  String? visitLabel(Outlet o) {
    final days = daysAway(o);
    return switch (days) {
      null => null,
      0 => 'Был сегодня',
      1 => 'Был вчера',
      < staleDays => 'Был ${plural(days, 'день', 'дня', 'дней')} назад',
      _ => 'Не был ${plural(days, 'день', 'дня', 'дней')}',
    };
  }

  /// Две плашки выбранного магазина на карте — по макету AgentShopsMap.
  List<Widget> chips(Outlet o) {
    final v = visitToday(o);
    if (v != null) {
      final order = visits.orderOf(v);
      return [
        if (order != null) Tag.ok('Сегодня ${time(v.startedAt)} · ${money(order.total)}')
        else Tag('Сегодня ${time(v.startedAt)} · без заказа'),
        if (order?.status == 'NEEDS_APPROVAL') const Tag.brand('Ждёт руководителя')
        else if (order != null && order.returnTotal > 0) Tag.warn('Возврат ${money(order.returnTotal)}')
        else if (order == null && v.reason != null) Tag(v.reason!)
        else if (o.mine) Tag(o.debt > 0 ? 'Долг ${money(o.debt)}' : 'Долга нет'),
      ];
    }
    if (o.pending) {
      final created = data.stats[o.id]?.createdOn;
      return [const Tag.brand('Новый · на проверке'), if (created != null) Tag('Создан ${dayMonth(created)}')];
    }
    final seen = visitLabel(o);
    if (o.mine && o.overdue > 0) return [Tag.warn('Просрочено ${money(o.overdue)}'), Tag('Долг ${money(o.debt)}')];
    final avg = data.stats[o.id]?.avgOrder ?? 0;
    return [
      if (o.mine && o.debt > 0) Tag('Долг ${money(o.debt)}') else if (avg > 0) Tag('Средний заказ ${money(avg)}'),
      if (seen != null) Tag(seen),
    ];
  }

  /// Плашка строки в списке: на проверке, просрочка, долг (у своих).
  Widget? listChip(Outlet o) {
    if (o.pending) return const Tag.brand('На проверке');
    if (o.mine && o.overdue > 0) return Tag.warn('Просрочено ${money(o.overdue)}');
    if (o.mine && o.debt > 0) return Tag('Долг ${money(o.debt)}');
    return null;
  }

  /// Ближние сверху, на одном расстоянии и без точки — как в базе.
  List<Outlet> byDistance(Iterable<Outlet> list) {
    final all = list.toList();
    final order = {for (final (i, o) in all.indexed) o.id: i};
    final dist = {for (final o in all) o.id: meters(o)};
    return all
      ..sort((a, b) {
        final da = dist[a.id], db = dist[b.id];
        if (da != null && db != null && da != db) return da.compareTo(db);
        if (da == null && db != null) return 1;
        if (da != null && db == null) return -1;
        return order[a.id]!.compareTo(order[b.id]!);
      });
  }

  /// Поиск по названию, адресу, ориентиру и владельцу.
  static bool matches(Outlet o, String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || [o.name, o.address, o.landmark, o.owner].nonNulls.join(' ').toLowerCase().contains(q);
  }
}
