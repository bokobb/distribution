import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api/api_client.dart';
import 'data/local_store.dart';
import 'data/track.dart';
import 'location.dart';

/// Рабочий день агента или экспедитора: «Начать день» / «Закончить день», точка GPS раз в [interval], пока день
/// открыт, и журнал приложения. Всё сначала записывается на телефон и уходит на сервер пачкой, когда есть сеть;
/// сервер принимает точки только рабочего дня. Состояние дня — по журналу на телефоне, поэтому переживает
/// перезапуск приложения.
class Workday extends ChangeNotifier {
  Workday({
    required this.api,
    required this.store,
    required this.location,
    this.interval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final ApiClient api;
  final LocalStore store;
  final LocationSource location;
  final DateTime Function() _now;

  /// Как часто снимать точку — из настроек компании ([setInterval]).
  Duration interval;

  /// Рабочий день открыт с; null — не начат или закончен.
  DateTime? get startedAt => _startedAt;

  /// Сегодня день закончен в.
  DateTime? get endedAt => _endedAt;
  bool get open => _startedAt != null;

  /// Последняя сохранённая точка GPS.
  DateTime? lastFix;

  /// Записей на телефоне ждут отправки.
  int unsent = 0;

  /// Местоположение на телефоне выключено, пока день открыт.
  bool gpsOff = false;

  /// Идёт «Начать день» (спрашиваем доступ к местоположению).
  bool busy = false;

  static const _batch = 500;

  DateTime? _startedAt;
  DateTime? _endedAt;
  DateTime? _lastSaved;
  StreamSubscription<Fix>? _fixes;
  StreamSubscription<bool>? _status;
  bool _sending = false;
  bool _again = false;
  bool _disposed = false;

  /// При запуске приложения: «Открыл приложение» в журнал и состояние дня по журналу; день открыт — GPS снова идёт.
  /// Вчерашний незакрытый день не продолжается: сервер считает его до конца той даты.
  Future<void> restore() async {
    await _log('APP_OPEN');
    final now = _now();
    DateTime? open, ended;
    for (final e in await store.eventsSince(DateTime(now.year, now.month, now.day))) {
      if (e.kind == 'DAY_START' && open == null) {
        open = e.at;
      } else if (e.kind == 'DAY_END' && open != null) {
        open = null;
        ended = e.at;
      }
    }
    _startedAt = open;
    _endedAt = ended;
    if (open != null) _track();
    unsent = await store.unsentCount();
    _changed();
    unawaited(flush());
  }

  /// «Начать день». Без доступа к местоположению день не начинается — тогда текст, что сделать человеку.
  Future<String?> start() async {
    if (open || busy) return null;
    busy = true;
    _changed();
    try {
      final problem = await location.ensureAccess();
      if (problem != null) return problem;
      final at = _now();
      await _log('DAY_START', at: at);
      _startedAt = at;
      _endedAt = null;
      _lastSaved = null;
      _track();
      return null;
    } finally {
      busy = false;
      _changed();
      unawaited(flush());
    }
  }

  /// «Закончить день»: GPS останавливается, в журнал — «Закончил день».
  Future<void> end() async {
    if (!open) return;
    await _stopTracking();
    final at = _now();
    await _log('DAY_END', at: at);
    _startedAt = null;
    _endedAt = at;
    _changed();
    await flush();
  }

  /// Интервал из настроек компании; день открыт — GPS перезапускается с новым.
  void setInterval(Duration value) {
    if (value == interval) return;
    interval = value;
    if (open) _track();
  }

  /// Отправить накопленное пачками. Нет сети — останется на телефоне до следующего раза. Попросили отправить,
  /// пока отправка уже идёт, — она пройдёт ещё круг и заберёт новое.
  Future<void> flush() async {
    if (_sending) {
      _again = true;
      return;
    }
    _sending = true;
    try {
      do {
        _again = false;
        while (true) {
          final batch = await store.unsent(_batch);
          if (batch.size == 0) break;
          final left = await store.unsentCount() - batch.size;
          await api.track(batch, unsent: left);
          await store.markSent(batch);
          if (batch.size < _batch) break;
        }
      } while (_again);
    } on ApiException {
      // нет сети, сервер недоступен или вход закрыт — отправим позже
    } finally {
      _sending = false;
      if (!_disposed) {
        unsent = await store.unsentCount();
        _changed();
      }
    }
  }

  /// Выход из приложения: GPS остановить.
  Future<void> stop() => _stopTracking();

  void _track() {
    _fixes?.cancel();
    _fixes = location.track(interval).listen(_onFix, onError: (Object _) {});
    _status ??= location.serviceStatus().listen(_onStatus, onError: (Object _) {});
  }

  Future<void> _stopTracking() async {
    await _fixes?.cancel();
    await _status?.cancel();
    _fixes = null;
    _status = null;
    gpsOff = false;
  }

  Future<void> _onFix(Fix f) async {
    // поток может присылать точки чаще, чем просили, — сохраняем не чаще интервала
    if (_lastSaved != null && f.at.difference(_lastSaved!) < interval * 0.9) return;
    _lastSaved = f.at;
    lastFix = f.at;
    await store.addPoint(
        TrackPoint(at: f.at, lat: f.lat, lng: f.lng, accuracy: f.accuracy, battery: await location.battery()));
    _changed();
    await flush();
  }

  Future<void> _onStatus(bool on) async {
    if (on != gpsOff) return; // не изменилось
    gpsOff = !on;
    await _log(on ? 'GPS_ON' : 'GPS_OFF');
    _changed();
    await flush();
  }

  Future<void> _log(String kind, {DateTime? at, String? note}) =>
      store.addEvent(TrackEvent(uuid: const Uuid().v4(), at: at ?? _now(), kind: kind, note: note));

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _fixes?.cancel();
    _status?.cancel();
    super.dispose();
  }
}
