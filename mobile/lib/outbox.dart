import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'data/local_store.dart';
import 'data/order.dart';
import 'data/visit.dart';

/// Всё, что ждёт отправки на сервер: журнал приложения и точки GPS (пачками), законченные визиты, фото полки
/// и заказы. Сначала пишется на телефон, отсюда уходит, когда есть сеть; нет сети — останется до следующего
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
        await _visits(); // визит раньше заказа: заказ ссылается на него
        await _orders();
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
    for (final photo in await store.pruneVisits(DateTime.now().subtract(keep))) {
      try {
        await File(photo).delete();
      } on FileSystemException {
        // уже нет
      }
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
    await store.pruneOrders(DateTime.now().subtract(keep));
  }

  /// Убрать с телефона визит, который сервер не принял (с фото).
  Future<void> dropVisit(Visit v) async {
    await store.deleteVisit(v.uuid);
    if (v.photo != null) {
      try {
        await File(v.photo!).delete();
      } on FileSystemException {
        // уже нет
      }
    }
    await count();
  }

  /// Убрать с телефона заказ, который сервер не принял.
  Future<void> dropOrder(Order o) async {
    await store.deleteOrder(o.uuid);
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
