import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'camera.dart';
import 'data/agent_data.dart';
import 'data/local_store.dart';
import 'data/order.dart';
import 'data/visit.dart';
import 'geo.dart';
import 'location.dart';
import 'outbox.dart';

/// Визиты и заказы агента за сегодня: начать визит в магазине (по GPS; дальше радиуса из настроек компании —
/// только подтвердив, директор увидит пометку «далеко»), фото полки, закончить заказом или без заказа с
/// причиной, отменить. Всё пишется на телефон и уходит через [outbox]; визиты и заказы с сервера (из данных
/// агента) показываются вместе с телефонными — отметки «был» переживают переустановку.

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
  List<Order> _localOrders = [];
  List<Order> _serverOrders = [];
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

  /// Заказы магазина сегодня: с телефона и с сервера (там свежий статус), без повторов, по времени.
  List<Order> ordersAt(int outletId) {
    final from = _today();
    final server = {for (final o in _serverOrders) o.uuid: o};
    final mine = {for (final o in _localOrders) o.uuid};
    return [
      for (final o in _localOrders)
        if (o.outletId == outletId && !o.createdAt.isBefore(from)) _fresher(o, server[o.uuid]),
      ..._serverOrders.where((o) => o.outletId == outletId && !mine.contains(o.uuid) && !o.createdAt.isBefore(from)),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Статус на сервере мог поменяться (разрешили, отменили) — показываем его.
  static Order _fresher(Order local, Order? server) {
    if (server == null || local.error != null) return local;
    return local.copy()
      ..status = server.status
      ..statusLabel = server.statusLabel
      ..note = server.note
      ..number = server.number
      ..total = server.total;
  }

  /// С телефона.
  Future<void> load() async {
    final local = await store.visitsSince(_today());
    final orders = await store.ordersSince(_today());
    if (_disposed) return;
    _local = local;
    _localOrders = orders;
    notifyListeners();
  }

  void _reload() => unawaited(load());

  /// Визиты и заказы за сегодня из данных агента с сервера.
  void serverVisits(AgentData data) {
    _server = data.visits;
    _serverOrders = data.orders;
    notifyListeners();
  }

  /// Начать визит там, где агент сейчас. Дальше радиуса от магазина — только если человек подтвердил
  /// ([confirmFar] с расстоянием); у магазина без точки на карте расстояние не считается.
  /// Не получилось — текст для человека.
  Future<String?> start(Outlet outlet,
      {int? routeId, required int radius, required Future<bool> Function(int distance) confirmFar}) async {
    if (current != null) return 'Сначала закончите начатый визит';
    final fix = await location.current();
    if (fix == null) return 'Не удалось определить, где вы. Проверьте, что местоположение включено, и нажмите ещё раз';
    int? distance;
    if (outlet.lat != null && outlet.lng != null) {
      distance = metersBetween(fix.lat, fix.lng, outlet.lat!, outlet.lng!);
      final allowance = (fix.accuracy ?? 0).clamp(0, accuracyAllowance);
      if (distance - allowance > radius && !await confirmFar(distance)) return null;
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

  /// Закончить визит заказом. Фото полки — если его требуют настройки; не хватает — текст для человека.
  Future<String?> finishWithOrder(
      {required Map<int, int> items,
      required int total,
      required String payment,
      required DateTime deliveryDate,
      String? comment,
      required AgentSettings settings}) async {
    final v = current;
    if (v == null) return 'Визит уже закончен';
    if (settings.shelfPhotoRequired && v.photo == null) return 'Сначала сфотографируйте полку';
    if (items.isEmpty) return 'В заказе нет товаров';
    final now = _now();
    final o = Order(
      uuid: const Uuid().v4(),
      visitUuid: v.uuid,
      outletId: v.outletId,
      createdAt: now,
      deliveryDate: DateTime(deliveryDate.year, deliveryDate.month, deliveryDate.day),
      payment: payment,
      comment: comment == null || comment.trim().isEmpty ? null : comment.trim(),
      items: {...items},
      total: total,
    );
    await store.saveOrder(o);
    v
      ..finishedAt = now
      ..result = 'ORDER'
      ..reason = null;
    await store.saveVisit(v);
    _localOrders.add(o);
    await store.remove(draftKey);
    notifyListeners();
    await outbox.count();
    unawaited(outbox.flush());
    return null;
  }

  /// Ключ черновика заказа на телефоне: товары не теряются, если приложение закрылось посреди заказа.
  static const draftKey = 'order-draft';

  /// Черновик заказа идущего визита: id товара → штук.
  Future<Map<int, int>> draft() async {
    final j = await store.read(draftKey);
    if (j == null || j['visit'] != current?.uuid) return {};
    return Order.parseItems(j['items'] as String);
  }

  Future<void> saveDraft(Map<int, int> items) async {
    final v = current;
    if (v == null) return;
    await store.write(draftKey, {'visit': v.uuid, 'items': Order.encodeItems(items)});
  }

  /// Начали визит по ошибке — стереть, на сервер он не уйдёт.
  Future<void> cancel() async {
    final v = current;
    if (v == null) return;
    await store.deleteVisit(v.uuid);
    await store.remove(draftKey);
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
