import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'camera.dart';
import 'data/debt_payment.dart';
import 'data/defect_return.dart';
import 'data/delivery.dart';
import 'data/expeditor_data.dart';
import 'data/local_store.dart';
import 'location.dart';
import 'outbox.dart';

/// Выдачи экспедитора: выдать заказ (всё или часть) и принять деньги, записать отказ магазина с причиной, принять
/// оплату старого долга и негодный товар; отменить, пока не ушло. Всё пишется на телефон и уходит через [outbox]; пока сервер не
/// ответил, точка рейса показывается по телефонной выдаче.
class DeliveryBook extends ChangeNotifier {
  DeliveryBook(
      {required this.store, required this.outbox, required this.location, required this.camera, DateTime Function()? clock})
      : _now = clock ?? DateTime.now {
    // отправка прошла — отметки «ждёт отправки» перечитать с телефона
    outbox.addListener(_reload);
  }

  final LocalStore store;
  final Outbox outbox;
  final LocationSource location;

  /// Фото накладной и файл подписи получателя.
  final PhotoSource camera;
  final DateTime Function() _now;

  /// Частые причины отказа — выбрать одним касанием.
  static const reasons = ['Магазин закрыт', 'Нет денег', 'Не заказывали', 'Передумали'];

  /// Дольше место не ждём: выдачу это не держит, координаты — только для карты.
  static const gpsWait = Duration(seconds: 8);

  List<Delivery> _local = [];
  List<DebtPayment> _payments = [];
  List<DefectReturn> _returns = [];
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

  /// Оплаты долга магазина за сегодня на телефоне — и непринятые сервером.
  List<DebtPayment> paymentsAt(int outletId) {
    final from = _today();
    return _payments.where((p) => p.outletId == outletId && !p.paidAt.isBefore(from)).toList();
  }

  /// Оплаты долга рейса на телефоне, которые сервер не отклонил.
  List<DebtPayment> paymentsIn(int tripId) => _payments.where((p) => p.tripId == tripId && p.error == null).toList();

  /// Возвраты рейса на телефоне, которые сервер не отклонил.
  List<DefectReturn> returnsIn(int tripId) => _returns.where((r) => r.tripId == tripId && r.error == null).toList();

  /// Возвраты негодного у магазина за сегодня на телефоне — и непринятые сервером.
  List<DefectReturn> returnsAt(int outletId) {
    final from = _today();
    return _returns.where((r) => r.outletId == outletId && !r.returnedAt.isBefore(from)).toList();
  }

  DateTime _today() {
    final n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> load() async {
    final local = await store.deliveries();
    final payments = await store.debtPayments();
    final returns = await store.returns();
    if (_disposed) return;
    _local = local;
    _payments = payments;
    _returns = returns;
    notifyListeners();
  }

  void _reload() => unawaited(load());

  /// Выдать заказ: [items] — сколько выдано по товарам (id → штук), всё как в заказе — выдано целиком;
  /// [cash] и [kaspi] — сколько получено; [proof] — файл подписи получателя или фото накладной. Не получилось —
  /// текст для человека.
  Future<String?> deliver(TripInfo trip, Stop stop,
      {required Map<int, int> items,
      int cash = 0,
      int kaspi = 0,
      String? proof,
      required ExpeditorSettings settings}) async {
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
        kaspi: kaspi,
        proof: proof);
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
      {String? refuseReason,
      Map<int, int> items = const {},
      int total = 0,
      int cash = 0,
      int kaspi = 0,
      String? proof}) async {
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
      proof: proof,
    );
    await store.saveDelivery(d);
    _local = [..._local.where((x) => x.uuid != rejected?.uuid), d];
    notifyListeners();
    await outbox.count();
    unawaited(outbox.flush());
  }

  /// Принять оплату старого долга: наличные и Kaspi — отдельными оплатами. Больше долга — остаток авансом
  /// (спрашивает экран). Не получилось — текст для человека.
  Future<String?> payDebt(TripInfo trip, Stop stop,
      {int cash = 0, int kaspi = 0, required ExpeditorSettings settings}) async {
    if (cash < 0 || kaspi < 0) return 'Сумма не может быть меньше нуля';
    if (cash + kaspi == 0) return 'Введите сумму';
    if (kaspi > 0 && !settings.acceptKaspi) return 'Kaspi компания не принимает';
    final at = _now();
    for (final (method, amount) in [('CASH', cash), ('KASPI', kaspi)]) {
      if (amount == 0) continue;
      final p = DebtPayment(
          uuid: const Uuid().v4(), outletId: stop.outlet.id, tripId: trip.id, method: method, amount: amount, paidAt: at);
      await store.saveDebtPayment(p);
      _payments = [..._payments, p];
    }
    notifyListeners();
    await outbox.count();
    unawaited(outbox.flush());
    return null;
  }

  /// Оплату приняли по ошибке — стереть, пока не ушла на сервер. Ушла — false.
  Future<bool> cancelPayment(DebtPayment p) async {
    final now = (await store.debtPayments()).where((x) => x.uuid == p.uuid).firstOrNull;
    if (now == null || now.sent) return false;
    await store.deleteDebtPayment(p.uuid);
    _payments = _payments.where((x) => x.uuid != p.uuid).toList();
    notifyListeners();
    await outbox.count();
    return true;
  }

  /// Принять негодный товар: [items] — id товара → штук; [total] — сумма по ценам на телефоне (точную посчитает
  /// сервер по цене дня); [plan] — по списку торгового. Не получилось — текст для человека.
  Future<String?> returnGoods(TripInfo trip, Stop stop,
      {required Map<int, int> items, required int total, bool plan = false}) async {
    final chosen = {for (final e in items.entries) if (e.value > 0) e.key: e.value};
    if (chosen.isEmpty) return 'Выберите товар';
    final r = DefectReturn(
        uuid: const Uuid().v4(),
        outletId: stop.outlet.id,
        tripId: trip.id,
        returnedAt: _now(),
        items: chosen,
        total: total,
        plan: plan);
    await store.saveReturn(r);
    _returns = [..._returns, r];
    notifyListeners();
    await outbox.count();
    unawaited(outbox.flush());
    return null;
  }

  /// Забрать у магазина всё, что торговый записал с заказом, — одним возвратом. Не получилось — текст.
  Future<String?> takePlannedReturns(TripInfo trip, Stop stop) => returnGoods(trip, stop,
      items: {for (final r in stop.order.returns) r.productId: r.qty},
      total: stop.order.returns.fold(0, (a, r) => a + r.sum),
      plan: true);

  /// Список торгового уже забран; сервер не принял — снова виден.
  bool plannedTaken(TripInfo trip, Stop stop) =>
      returnsAt(stop.outlet.id).any((r) => r.plan && r.tripId == trip.id && r.error == null);

  /// Возврат записали по ошибке — стереть, пока не ушёл на сервер. Ушёл — false.
  Future<bool> cancelReturn(DefectReturn r) async {
    final now = (await store.returns()).where((x) => x.uuid == r.uuid).firstOrNull;
    if (now == null || now.sent) return false;
    await store.deleteReturn(r.uuid);
    _returns = _returns.where((x) => x.uuid != r.uuid).toList();
    notifyListeners();
    await outbox.count();
    return true;
  }

  /// Выдали не тому или не то — стереть, пока выдача не ушла на сервер. Ушла — false.
  Future<bool> cancel(Delivery d) async {
    final now = (await store.deliveries()).where((x) => x.uuid == d.uuid).firstOrNull;
    if (now == null || now.sent) return false;
    await store.deleteDelivery(d.uuid);
    final proof = now.proof;
    if (proof != null) {
      try {
        await File(proof).delete();
      } on FileSystemException {
        // уже нет
      }
    }
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
