import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'camera.dart';
import 'data/agent_data.dart';
import 'data/local_store.dart';
import 'data/visit.dart';
import 'geo.dart';
import 'location.dart';
import 'outbox.dart';

/// Визиты агента за сегодня: начать визит в магазине (GPS — не дальше радиуса из настроек компании), фото полки,
/// закончить без заказа с причиной или отменить. Визиты пишутся на телефон и уходят через [outbox]; визиты
/// с сервера (из данных агента) показываются вместе с телефонными — отметки «был» переживают переустановку.
class VisitBook extends ChangeNotifier {
  VisitBook({
    required this.store,
    required this.outbox,
    required this.location,
    required this.camera,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    // отправка прошла — отметки «ждёт отправки» перечитать с телефона
    outbox.addListener(_reload);
  }

  final LocalStore store;
  final Outbox outbox;
  final LocationSource location;
  final PhotoSource camera;
  final DateTime Function() _now;

  /// Точность GPS засчитывается в пользу агента, но не больше стольких метров.
  static const accuracyAllowance = 50;

  /// Частые причины «без заказа» — выбрать одним касанием.
  static const reasons = [
    'Товар ещё есть',
    'Нет денег',
    'Хозяина нет на месте',
    'Магазин закрыт',
    'Берёт у другого поставщика',
  ];

  List<Visit> _local = [];
  List<Visit> _server = [];
  bool _disposed = false;

  /// Визит идёт; null — нет.
  Visit? get current => _local.where((v) => v.open).firstOrNull;

  /// Сегодняшние визиты: с телефона и с сервера, без повторов, по времени.
  List<Visit> get today {
    final from = _today();
    final mine = {for (final v in _local) v.uuid};
    return [
      ..._local.where((v) => !v.startedAt.isBefore(from)),
      ..._server.where((v) => !mine.contains(v.uuid) && !v.startedAt.isBefore(from)),
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  /// Последний визит в магазин сегодня.
  Visit? lastAt(int outletId) => today.where((v) => v.outletId == outletId).lastOrNull;

  /// С телефона.
  Future<void> load() async {
    final local = await store.visitsSince(_today());
    if (_disposed) return;
    _local = local;
    notifyListeners();
  }

  void _reload() => unawaited(load());

  /// Визиты за сегодня из данных агента с сервера.
  void serverVisits(AgentData data) {
    _server = data.visits;
    notifyListeners();
  }

  /// Начать визит. Магазин с точкой на карте — только рядом с ним; без точки — где агент сейчас.
  /// Не получилось — текст для человека.
  Future<String?> start(Outlet outlet, {int? routeId, required int radius}) async {
    if (current != null) return 'Сначала закончите начатый визит';
    final fix = await location.current();
    if (fix == null) return 'Не удалось определить, где вы. Проверьте, что местоположение включено, и нажмите ещё раз';
    int? distance;
    if (outlet.lat != null && outlet.lng != null) {
      distance = metersBetween(fix.lat, fix.lng, outlet.lat!, outlet.lng!);
      final allowance = (fix.accuracy ?? 0).clamp(0, accuracyAllowance);
      if (distance - allowance > radius) {
        return 'Вы в ${distanceLabel(distance)} от магазина — визит начинается не дальше $radius м. '
            'Подойдите к магазину и нажмите ещё раз';
      }
    }
    final v = Visit(
      uuid: const Uuid().v4(),
      outletId: outlet.id,
      routeId: routeId,
      startedAt: _now(),
      lat: fix.lat,
      lng: fix.lng,
      accuracy: fix.accuracy,
      distance: distance,
    );
    await store.saveVisit(v);
    _local.add(v);
    notifyListeners();
    return null;
  }

  /// Снять фото полки к идущему визиту; переснять — прежнее стирается. Камера не открылась — текст для человека.
  Future<String?> takePhoto() async {
    final v = current;
    if (v == null) return null;
    final String? path;
    try {
      path = await camera.shelf(v.uuid);
    } on Exception {
      return 'Не удалось открыть камеру';
    }
    if (path == null) return null;
    final old = v.photo;
    v.photo = path;
    await store.saveVisit(v);
    if (old != null) await _delete(old);
    notifyListeners();
    return null;
  }

  /// Закончить без заказа. Причина и фото — если их требуют настройки; не хватает — текст для человека.
  Future<String?> finishNoOrder(String? reason, AgentSettings settings) async {
    final v = current;
    if (v == null) return null;
    final why = reason?.trim();
    if (settings.shelfPhotoRequired && v.photo == null) return 'Сначала сфотографируйте полку';
    if (settings.refuseReasonRequired && (why == null || why.isEmpty)) return 'Укажите, почему без заказа';
    v
      ..finishedAt = _now()
      ..result = 'NO_ORDER'
      ..reason = why == null || why.isEmpty ? null : why;
    await store.saveVisit(v);
    notifyListeners();
    await outbox.count();
    unawaited(outbox.flush());
    return null;
  }

  /// Начали визит по ошибке — стереть, на сервер он не уйдёт.
  Future<void> cancel() async {
    final v = current;
    if (v == null) return;
    await store.deleteVisit(v.uuid);
    _local.remove(v);
    if (v.photo != null) await _delete(v.photo!);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    outbox.removeListener(_reload);
    super.dispose();
  }

  DateTime _today() {
    final n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // уже нет
    }
  }
}
