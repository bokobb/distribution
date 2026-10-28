import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'data/debt_payment.dart';
import 'data/defect_return.dart';
import 'data/delivery.dart';
import 'data/local_store.dart';
import 'data/new_outlet.dart';
import 'data/order.dart';
import 'data/visit.dart';

/// Всё, что ждёт отправки на сервер: журнал приложения и точки GPS (пачками), новые магазины с фото фасада,
/// законченные визиты, фото полки, заказы, выдачи экспедитора, оплаты долга и возвраты негодного. Сначала пишется на телефон, отсюда уходит, когда есть сеть; нет сети — останется до следующего
/// раза: отправка повторяется сама раз в [retry], пока есть что отправить ([start]), и при возврате в
/// приложение. Повтор не задваивает: у записей журнала, визитов и заказов uuid телефона, у точек — время.
class Outbox extends ChangeNotifier {
  Outbox({required this.api, required this.store, this.retry = const Duration(minutes: 1), DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final ApiClient api;
  final LocalStore store;
  final Duration retry;
  final DateTime Function() _now;

  /// Записей на телефоне ждут отправки.
  int unsent = 0;

  /// Когда последний раз всё ушло; почему последняя отправка не прошла (нет сети и т. п.) — null, если прошла.
  DateTime? lastOk;
  String? lastError;

  /// Отправка идёт.
  bool get sending => _sending;

  /// Сколько новых магазинов сервер принял за это время: вырос — данные агента пора обновить (там они уже
  /// в маршруте «на проверке»).
  int outletsAdded = 0;

  /// Сколько выдач, оплат долга и возвратов сервер принял за это время: вырос — данные экспедитора пора обновить
  /// (статусы и долги).
  int expeditorSent = 0;

  static const _batch = 500;

  /// Отправленные визиты с фото и заказы держим на телефоне столько, потом стираем.
  static const keep = Duration(days: 3);

  bool _sending = false;
  bool _again = false;
  bool _disposed = false;
  Timer? _timer;

  /// Повторять отправку раз в [retry], пока есть что отправить.
  void start() {
    _timer ??= Timer.periodic(retry, (_) {
      if (unsent > 0) unawaited(flush());
    });
  }

  /// Отправить всё накопленное. Попросили отправить, пока отправка уже идёт, — она пройдёт ещё круг и
  /// заберёт новое.
  Future<void> flush() async {
    if (_sending) {
      _again = true;
      return;
    }
    _sending = true;
    if (!_disposed) notifyListeners();
    try {
      do {
        _again = false;
        await _track();
        await _outlets();
        await _visits(); // визит раньше заказа: заказ ссылается на него
        await _orders();
        await _deliveries();
        await _debtPayments(); // после выдач: долг на сервере уже с ними
        await _returns();
      } while (_again);
      lastOk = _now();
      lastError = null;
    } on ApiException catch (e) {
      // нет сети, сервер недоступен или вход закрыт — отправим позже
      lastError = e.message;
    } finally {
      _sending = false;
      await count();
    }
  }

  /// Пересчитать, сколько ждёт отправки (записали новое на телефон).
  Future<void> count() async {
    if (_disposed) return;
    unsent = await store.unsentCount();
    if (!_disposed) notifyListeners();
  }

  Future<void> _track() async {
    while (true) {
      final batch = await store.unsent(_batch);
      if (batch.size == 0) break;
      final left = await store.unsentCount() - batch.size;
      await api.track(batch, unsent: left);
      await store.markSent(batch);
      if (batch.size < _batch) break;
    }
  }

  /// Визит, потом его фото. Сервер визит не принял (неверные данные) — помечаем и идём дальше, чтобы один
  /// визит не держал остальные; нет связи — останавливаемся до следующего раза.
  Future<void> _visits() async {
    for (final v in await store.visitsToSend()) {
      try {
        if (!v.sent) {
          await api.visit(v.toJson());
          v.sent = true;
          await store.saveVisit(v);
        }
        final photo = v.photo;
        if (photo != null && !v.photoSent) {
          final file = File(photo);
          if (await file.exists()) await api.visitPhoto(v.uuid, await file.readAsBytes());
          v.photoSent = true;
          await store.saveVisit(v);
        }
      } on ApiException catch (e) {
        if (!_rejected(e)) rethrow;
        v.error = e.message;
        await store.saveVisit(v);
      }
    }
    for (final photo in await store.pruneVisits(_now().subtract(keep))) {
      await _deleteFile(photo);
    }
  }

  /// Новый магазин, потом фото фасада. Не принят — помечаем и идём дальше.
  Future<void> _outlets() async {
    for (final o in await store.newOutlets()) {
      if (o.error != null || o.sent && (o.photo == null || o.photoSent)) continue;
      try {
        if (!o.sent) {
          await api.newOutlet(o.toJson());
          o.sent = true;
          outletsAdded++;
          await store.saveNewOutlet(o);
        }
        final photo = o.photo;
        if (photo != null && !o.photoSent) {
          final file = File(photo);
          if (await file.exists()) await api.outletPhoto(o.uuid, await file.readAsBytes());
          o.photoSent = true;
          await store.saveNewOutlet(o);
        }
      } on ApiException catch (e) {
        if (!_rejected(e)) rethrow;
        o.error = e.message;
        await store.saveNewOutlet(o);
      }
    }
    for (final photo in await store.pruneNewOutlets(_now().subtract(keep))) {
      await _deleteFile(photo);
    }
  }

  /// Заказ; сервер вернул номер, статус и свой итог. Не принял — помечаем и идём дальше.
  Future<void> _orders() async {
    for (final o in await store.ordersToSend()) {
      try {
        o.takeServer(await api.order(o.toJson()));
      } on ApiException catch (e) {
        if (!_rejected(e)) rethrow;
        o.error = e.message;
      }
      await store.saveOrder(o);
    }
    await store.pruneOrders(_now().subtract(keep));
  }

  /// Выдача экспедитора; сервер вернул статус заказа и свои суммы. Не принял — помечаем и идём дальше.
  Future<void> _deliveries() async {
    for (final d in await store.deliveries()) {
      if (d.sent || d.error != null) continue;
      try {
        final r = await api.delivery(d.toJson());
        d
          ..sent = true
          ..statusLabel = r['statusLabel'] as String?;
        expeditorSent++;
      } on ApiException catch (e) {
        if (!_rejected(e)) rethrow;
        d.error = e.message;
      }
      await store.saveDelivery(d);
    }
    await store.pruneDeliveries(_now().subtract(keep));
  }

  /// Оплата старого долга; сервер вернул долг магазина после неё. Не принял — помечаем и идём дальше.
  Future<void> _debtPayments() async {
    for (final p in await store.debtPayments()) {
      if (p.sent || p.error != null) continue;
      try {
        final r = await api.debtPayment(p.toJson());
        p
          ..sent = true
          ..debtAfter = r['debt'] as int?;
        expeditorSent++;
      } on ApiException catch (e) {
        if (!_rejected(e)) rethrow;
        p.error = e.message;
      }
      await store.saveDebtPayment(p);
    }
    await store.pruneDebtPayments(_now().subtract(keep));
  }

  /// Возврат негодного; сервер вернул сумму по своим ценам и долг магазина после него. Не принял — помечаем и идём
  /// дальше.
  Future<void> _returns() async {
    for (final r in await store.returns()) {
      if (r.sent || r.error != null) continue;
      try {
        final got = await api.defectReturn(r.toJson());
        r
          ..sent = true
          ..total = got['total'] as int? ?? r.total
          ..debtAfter = got['debt'] as int?;
        expeditorSent++;
      } on ApiException catch (e) {
        if (!_rejected(e)) rethrow;
        r.error = e.message;
      }
      await store.saveReturn(r);
    }
    await store.pruneReturns(_now().subtract(keep));
  }

  /// Убрать с телефона визит, который сервер не принял (с фото).
  Future<void> dropVisit(Visit v) async {
    await store.deleteVisit(v.uuid);
    if (v.photo != null) await _deleteFile(v.photo!);
    await count();
  }

  /// Убрать с телефона новый магазин, который сервер не принял (с фото).
  Future<void> dropOutlet(NewOutlet o) async {
    await store.deleteNewOutlet(o.uuid);
    if (o.photo != null) await _deleteFile(o.photo!);
    await count();
  }

  static Future<void> _deleteFile(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // уже нет
    }
  }

  /// Убрать с телефона заказ, который сервер не принял.
  Future<void> dropOrder(Order o) async {
    await store.deleteOrder(o.uuid);
    await count();
  }

  /// Убрать с телефона выдачу, которую сервер не принял.
  Future<void> dropDelivery(Delivery d) async {
    await store.deleteDelivery(d.uuid);
    await count();
  }

  /// Убрать с телефона оплату долга, которую сервер не принял.
  Future<void> dropDebtPayment(DebtPayment p) async {
    await store.deleteDebtPayment(p.uuid);
    await count();
  }

  /// Убрать с телефона возврат, который сервер не принял.
  Future<void> dropReturn(DefectReturn r) async {
    await store.deleteReturn(r.uuid);
    await count();
  }

  /// Сервер ответил, что запись неверна, — повтор не поможет.
  static bool _rejected(ApiException e) => const {400, 404, 409, 413, 415, 422}.contains(e.status);

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
