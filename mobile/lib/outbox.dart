import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'data/local_store.dart';

/// Всё, что ждёт отправки на сервер: журнал приложения и точки GPS (пачками), законченные визиты и фото полки.
/// Сначала пишется на телефон, отсюда уходит, когда есть сеть; нет сети — останется до следующего раза.
/// Повтор не задваивает: у записей журнала и визитов uuid телефона, у точек — время.
class Outbox extends ChangeNotifier {
  Outbox({required this.api, required this.store});

  final ApiClient api;
  final LocalStore store;

  /// Записей на телефоне ждут отправки.
  int unsent = 0;

  static const _batch = 500;

  /// Отправленные визиты и их фото держим на телефоне столько, потом стираем.
  static const keep = Duration(days: 3);

  bool _sending = false;
  bool _again = false;
  bool _disposed = false;

  /// Отправить всё накопленное. Попросили отправить, пока отправка уже идёт, — она пройдёт ещё круг и
  /// заберёт новое.
  Future<void> flush() async {
    if (_sending) {
      _again = true;
      return;
    }
    _sending = true;
    try {
      do {
        _again = false;
        await _track();
        await _visits();
      } while (_again);
    } on ApiException {
      // нет сети, сервер недоступен или вход закрыт — отправим позже
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

  /// Сервер ответил, что запись неверна, — повтор не поможет.
  static bool _rejected(ApiException e) => const {400, 404, 409, 413, 415, 422}.contains(e.status);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
