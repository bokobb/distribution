import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/delivery.dart';
import 'data/expeditor_data.dart';
import 'data/local_store.dart';
import 'location.dart';
import 'outbox.dart';

/// Выдачи экспедитора: выдать заказ (всё или часть) и принять деньги, записать отказ магазина с причиной,
/// отменить выдачу, пока она не ушла. Всё пишется на телефон и уходит через [outbox]; пока сервер не ответил,
/// точка рейса показывается по телефонной выдаче.
class DeliveryBook extends ChangeNotifier {
  DeliveryBook({required this.store, required this.outbox, required this.location, DateTime Function()? clock})
      : _now = clock ?? DateTime.now {
    // отправка прошла — отметки «ждёт отправки» перечитать с телефона
    outbox.addListener(_reload);
  }

  final LocalStore store;
  final Outbox outbox;
  final LocationSource location;
  final DateTime Function() _now;

  /// Частые причины отказа — выбрать одним касанием.
  static const reasons = ['Магазин закрыт', 'Нет денег', 'Не заказывали', 'Передумали'];

  /// Дольше место не ждём: выдачу это не держит, координаты — только для карты.
  static const gpsWait = Duration(seconds: 8);

  List<Delivery> _local = [];
  bool _disposed = false;

  /// Последняя выдача заказа на телефоне; null — не выдавали.
  Delivery? of(int orderId) => _local.where((d) => d.orderId == orderId).lastOrNull;

  /// Заказ пройден: так говорит сервер или на телефоне есть выдача, которую сервер не отклонил.
  bool done(TripOrder o) {
    final d = of(o.id);
    return o.done || d != null && d.error == null;
  }

  /// Сколько точек рейса пройдено с учётом выдач на телефоне.
  int doneIn(TripInfo t) => t.stops.where((s) => done(s.order)).length;

  Future<void> load() async {
    final local = await store.deliveries();
    if (_disposed) return;
    _local = local;
    notifyListeners();
  }

  void _reload() => unawaited(load());

  /// Выдать заказ: [items] — сколько выдано по товарам (id → штук), всё как в заказе — выдано целиком;
  /// [cash] и [kaspi] — сколько получено. Не получилось — текст для человека.
  Future<String?> deliver(TripInfo trip, Stop stop,
      {required Map<int, int> items, int cash = 0, int kaspi = 0, required ExpeditorSettings settings}) async {
    final order = stop.order;
    if (done(order)) return 'Заказ уже выдан';
    var total = 0;
    var all = true;
    for (final l in order.lines) {
      final qty = items[l.productId] ?? 0;
      if (qty < 0 || qty > l.qty) return 'По «${l.name}» можно выдать не больше ${l.qty}';
      if (qty != l.qty) all = false;
      total += qty * l.price;
    }
    if (items.values.every((q) => q == 0)) return 'Ничего не выдано — отметьте отказ';
    if (cash < 0 || kaspi < 0) return 'Сумма не может быть меньше нуля';
    if (kaspi > 0 && !settings.acceptKaspi) return 'Kaspi компания не принимает';
    if (cash + kaspi > total) return 'Получено больше, чем выдано';
    await _save(trip, stop,
        items: all ? const {} : {for (final e in items.entries) if (e.value > 0) e.key: e.value},
        total: total,
        cash: cash,
        kaspi: kaspi);
    return null;
  }

  /// Магазин отказался от заказа; причина обязательна.
  Future<String?> refuse(TripInfo trip, Stop stop, String reason) async {
    if (done(stop.order)) return 'Заказ уже выдан';
    final why = reason.trim();
    if (why.isEmpty) return 'Укажите, почему отказ';
    await _save(trip, stop, refuseReason: why);
    return null;
  }

  Future<void> _save(TripInfo trip, Stop stop,
      {String? refuseReason, Map<int, int> items = const {}, int total = 0, int cash = 0, int kaspi = 0}) async {
    final fix = await location.current().timeout(gpsWait, onTimeout: () => null);
    // прежняя выдача, которую сервер не принял, заменяется новой
    final rejected = of(stop.order.id);
    if (rejected != null) await store.deleteDelivery(rejected.uuid);
    final d = Delivery(
      uuid: const Uuid().v4(),
      orderId: stop.order.id,
      tripId: trip.id,
      outletId: stop.outlet.id,
      deliveredAt: _now(),
      refuseReason: refuseReason,
      items: items,
      total: total,
      cash: cash,
      kaspi: kaspi,
      cashUuid: const Uuid().v4(),
      kaspiUuid: const Uuid().v4(),
      lat: fix?.lat,
      lng: fix?.lng,
    );
    await store.saveDelivery(d);
    _local = [..._local.where((x) => x.uuid != rejected?.uuid), d];
    notifyListeners();
    await outbox.count();
    unawaited(outbox.flush());
  }

  /// Выдали не тому или не то — стереть, пока выдача не ушла на сервер. Ушла — false.
  Future<bool> cancel(Delivery d) async {
    final now = (await store.deliveries()).where((x) => x.uuid == d.uuid).firstOrNull;
    if (now == null || now.sent) return false;
    await store.deleteDelivery(d.uuid);
    _local = _local.where((x) => x.uuid != d.uuid).toList();
    notifyListeners();
    await outbox.count();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    outbox.removeListener(_reload);
    super.dispose();
  }
}
