import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api/api_client.dart';
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
/// агента) показываются вместе с телефонными — отметки «был» переживают переустановку. Заказ, пока его не
/// отгрузили, можно изменить или отменить.

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

  /// Частые причины «без заказа» — выбрать одним касанием; есть ещё «Другая причина» — своими словами.
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

  /// Все заказы агента за сегодня — для итогов дня.
  List<Order> get todayOrders {
    final from = _today();
    final server = {for (final o in _serverOrders) o.uuid: o};
    final mine = {for (final o in _localOrders) o.uuid};
    return [
      for (final o in _localOrders)
        if (!o.createdAt.isBefore(from)) _fresher(o, server[o.uuid]),
      ..._serverOrders.where((o) => !mine.contains(o.uuid) && !o.createdAt.isBefore(from)),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Заказ визита, если визит закончился заказом.
  Order? orderOf(Visit v) => todayOrders.where((o) => o.visitUuid == v.uuid).firstOrNull;

  /// Статус на сервере мог поменяться (разрешили, отменили) — показываем его.
  static Order _fresher(Order local, Order? server) {
    if (server == null || local.error != null) return local;
    return local.copy()
      ..status = server.status
      ..statusLabel = server.statusLabel
      ..note = server.note
      ..number = server.number
      ..total = server.total
      ..returnTotal = server.returnTotal;
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
    _serverOrders = [...data.orders]; // правка заказа меняет свой список, не данные агента
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
      path = await camera.photo(v.uuid);
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
      List<ReturnItem> returns = const [],
      int returnTotal = 0,
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
      returns: [...returns],
      returnTotal: returnTotal,
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

  /// Изменить заказ: товары, возврат, оплату, день доставки, комментарий. Заказ ещё на телефоне — переписать его там
  /// (уйдёт уже изменённым); уже на сервере — сразу туда: нужна сеть, и заказ не должен быть отгружен. Не
  /// получилось — текст для человека.
  Future<String?> editOrder(Order old,
      {required Map<int, int> items,
      required int total,
      List<ReturnItem> returns = const [],
      int returnTotal = 0,
      required String payment,
      required DateTime deliveryDate,
      String? comment}) async {
    if (items.isEmpty) return 'В заказе нет товаров';
    Order change(Order o) => o.edited(
        items: items,
        total: total,
        returns: returns,
        returnTotal: returnTotal,
        payment: payment,
        deliveryDate: DateTime(deliveryDate.year, deliveryDate.month, deliveryDate.day),
        comment: comment == null || comment.trim().isEmpty ? null : comment.trim());
    return outbox.paused(() async {
      final stored = await _stored(old.uuid);
      if (stored != null && !stored.sent && stored.error == null) {
        final o = change(stored);
        await store.saveOrder(o);
        _put(o);
        return null;
      }
      final o = change(stored ?? old);
      try {
        o.takeServer(await outbox.api.editOrder(o.uuid, o.editJson()));
      } on ApiException catch (e) {
        return _offline(e);
      }
      if (stored != null) await store.saveOrder(o);
      _put(o);
      return null;
    });
  }

  /// Отменить заказ. Ещё на телефоне — стереть его (визит, если тоже не ушёл, — «без заказа» с этой причиной); уже на
  /// сервере — отменить там: заказ останется в истории «Отменён». Не получилось — текст для человека.
  Future<String?> cancelOrder(Order old, String reason) async {
    final why = reason.trim();
    if (why.isEmpty) return 'Укажите, почему отменяете заказ';
    return outbox.paused(() async {
      final stored = await _stored(old.uuid);
      if (stored != null && !stored.sent && stored.error == null) {
        await store.deleteOrder(stored.uuid);
        _localOrders.removeWhere((o) => o.uuid == stored.uuid);
        final v = _local.where((v) => v.uuid == stored.visitUuid && !v.sent).firstOrNull;
        if (v != null) {
          v
            ..result = 'NO_ORDER'
            ..reason = 'Заказ отменён: $why';
          await store.saveVisit(v);
        }
        notifyListeners();
        await outbox.count();
        return null;
      }
      final o = (stored ?? old).copy();
      try {
        o.takeServer(await outbox.api.cancelOrder(o.uuid, why));
      } on ApiException catch (e) {
        return _offline(e);
      }
      if (stored != null) await store.saveOrder(o);
      _put(o);
      return null;
    });
  }

  Future<Order?> _stored(String uuid) async =>
      (await store.ordersSince(DateTime(2000))).where((o) => o.uuid == uuid).firstOrNull;

  /// Заказ после правки — вместо прежнего и среди телефонных, и среди серверных за сегодня.
  void _put(Order o) {
    for (final list in [_localOrders, _serverOrders]) {
      final i = list.indexWhere((x) => x.uuid == o.uuid);
      if (i >= 0) list[i] = o;
    }
    notifyListeners();
  }

  static String _offline(ApiException e) =>
      e.status == null ? 'Нет связи с сервером — заказ уже отправлен, изменить его можно только со связью' : e.message;

  /// Ключ черновика заказа на телефоне: товары не теряются, если приложение закрылось посреди заказа.
  static const draftKey = 'order-draft';

  /// Черновик заказа идущего визита: товары (id → штук) и возврат.
  Future<({Map<int, int> items, List<ReturnItem> returns})> draft() async {
    final j = await store.read(draftKey);
    if (j == null || j['visit'] != current?.uuid) return (items: <int, int>{}, returns: const <ReturnItem>[]);
    return (items: Order.parseItems(j['items'] as String), returns: Order.parseReturns(j['returns'] as String?));
  }

  Future<void> saveDraft(Map<int, int> items, [List<ReturnItem> returns = const []]) async {
    final v = current;
    if (v == null) return;
    await store.write(draftKey, {'visit': v.uuid, 'items': Order.encodeItems(items), 'returns': Order.encodeReturns(returns)});
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
