import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/local_store.dart';
import 'data/track.dart';
import 'location.dart';
import 'outbox.dart';

/// Рабочий день агента или экспедитора: «Начать день» / «Закончить день», точка GPS раз в [interval], пока день
/// открыт, и журнал приложения. Всё сначала записывается на телефон и уходит на сервер через [outbox], когда
/// есть сеть; сервер принимает точки только рабочего дня. Состояние дня — по журналу на телефоне, поэтому
/// переживает перезапуск приложения.
///
/// Рабочее время компании ([setHours]): сотрудник открыл приложение в эти часы ([opened]) — день начинается сам,
/// если доступ к местоположению уже разрешён и сегодня день не закрывали; в конце рабочего времени день
/// закрывается сам. Начатый вручную после конца рабочего времени — только вручную.
class Workday extends ChangeNotifier {
  Workday({
    required this.outbox,
    required this.store,
    required this.location,
    this.interval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    outbox.addListener(_changed);
  }

  final Outbox outbox;
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

  /// Последняя сохранённая точка GPS: когда и где (где — для расстояний до магазинов в списках).
  DateTime? lastFix;
  Fix? lastPlace;

  /// Записей на телефоне ждут отправки.
  int get unsent => outbox.unsent;

  /// Местоположение на телефоне выключено, пока день открыт.
  bool gpsOff = false;

  /// Идёт «Начать день» (спрашиваем доступ к местоположению).
  bool busy = false;

  /// День начинается сам, а доступа к местоположению нет — подсказка на главной.
  bool noAccess = false;

  /// В журнал — день начат или закончен сам, по рабочему времени.
  static const auto = 'сам, по рабочему времени';

  DateTime? _startedAt;
  DateTime? _endedAt;

  /// Рабочее время — минуты от полуночи; null — не знаем, день сам не начинается и не заканчивается.
  int? _from;
  int? _to;

  /// Сотрудник в приложении: открыл, не под замком.
  bool _present = false;
  bool _restored = false;
  Timer? _clock;
  DateTime? _lastSaved;
  StreamSubscription<Fix>? _fixes;
  StreamSubscription<bool>? _status;
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
    _restored = true;
    _changed();
    _plan();
    unawaited(flush());
  }

  /// «с 08:00 до 20:00»; рабочее время не знаем — null.
  String? get hours => _from == null || _to == null ? null : 'с ${_hhmm(_from!)} до ${_hhmm(_to!)}';

  /// Рабочее время из настроек компании, «08:00» и «20:00».
  void setHours(String? from, String? to) {
    var f = _minutes(from), t = _minutes(to);
    if (f == null || t == null || f >= t) f = t = null;
    if (f == _from && t == _to) return;
    _from = f;
    _to = t;
    _changed();
    _plan();
  }

  /// Сотрудник открыл приложение (или снял замок): рабочее время — день начинается сам.
  void opened() {
    _present = true;
    noAccess = false; // мог разрешить в настройках телефона, пока приложение было свёрнуто
    _plan();
  }

  /// Приложение свернули.
  void away() {
    _present = false;
    _plan();
  }

  /// «Начать день». Без доступа к местоположению день не начинается — тогда текст, что сделать человеку.
  Future<String?> start() async {
    if (open || busy) return null;
    busy = true;
    _changed();
    try {
      final problem = await location.ensureAccess();
      if (problem != null) return problem;
      noAccess = false;
      await _begin();
      return null;
    } finally {
      busy = false;
      _changed();
      _plan();
      unawaited(flush());
    }
  }

  /// «Закончить день»: GPS останавливается, в журнал — «Закончил день».
  Future<void> end() => _finish();

  Future<void> _begin({String? note}) async {
    final at = _now();
    await _log('DAY_START', at: at, note: note);
    _startedAt = at;
    _endedAt = null;
    _lastSaved = null;
    _track();
  }

  Future<void> _finish({DateTime? at, String? note}) async {
    if (!open) return;
    final end = at ?? _now();
    // сразу: второй вызов (таймер и точка GPS одновременно) день уже не закроет
    _startedAt = null;
    _endedAt = end;
    _clock?.cancel();
    unawaited(_stopTracking());
    await _log('DAY_END', at: end, note: note);
    _changed();
    await flush();
  }

  /// По рабочему времени. День идёт и начат до конца рабочего времени — закрыть в конце (прошёл — сразу, временем
  /// конца). Не идёт, сотрудник в приложении, сегодня день не закрывали — начать: сейчас или в начале рабочего
  /// времени.
  void _plan() {
    _clock?.cancel();
    _clock = null;
    final from = _from, to = _to;
    if (!_restored || busy || from == null || to == null) return;
    final now = _now();
    final started = _startedAt;
    if (started != null) {
      final end = _at(started, to);
      if (!started.isBefore(end)) return;
      if (now.isBefore(end)) {
        _clock = Timer(end.difference(now), _plan);
      } else {
        unawaited(_finish(at: end, note: auto));
      }
      return;
    }
    final ended = _endedAt;
    if (!_present || noAccess || (ended != null && _sameDay(ended, now))) return;
    final start = _at(now, from);
    if (now.isBefore(start)) {
      _clock = Timer(start.difference(now), _plan);
    } else if (now.isBefore(_at(now, to))) {
      unawaited(_autoStart());
    }
  }

  /// Без вопросов человеку: нет разрешения — день не начинается, на главной подсказка и «Начать рабочий день».
  Future<void> _autoStart() async {
    busy = true;
    _changed();
    try {
      if (!await location.allowed()) {
        noAccess = true;
        return;
      }
      if (open) return;
      await _begin(note: auto);
      // поток включения GPS сообщает только об изменениях — выключенный сейчас видно лишь так
      if (!await location.gpsOn()) {
        gpsOff = true;
        await _log('GPS_OFF');
      }
    } finally {
      busy = false;
      _changed();
      _plan();
      unawaited(flush());
    }
  }

  /// Интервал из настроек компании; день открыт — GPS перезапускается с новым.
  void setInterval(Duration value) {
    if (value == interval) return;
    interval = value;
    if (open) _track();
  }

  /// Отправить накопленное (Outbox).
  Future<void> flush() => outbox.flush();

  /// Выход из приложения: GPS остановить.
  Future<void> stop() {
    _clock?.cancel();
    _present = false;
    return _stopTracking();
  }

  void _track() {
    _fixes?.cancel();
    _fixes = location.track(interval).listen(_onFix, onError: (Object _) {});
    _status ??= location.serviceStatus().listen(_onStatus, onError: (Object _) {});
  }

  /// Подписки снимаются сразу — точки после этого не приходят; ждать стоит только самой службы GPS.
  Future<void> _stopTracking() {
    final fixes = _fixes, status = _status;
    _fixes = null;
    _status = null;
    gpsOff = false;
    return Future.wait([?fixes?.cancel(), ?status?.cancel()]);
  }

  Future<void> _onFix(Fix f) async {
    _plan(); // рабочее время кончилось, а таймер проспал (телефон спал) — день закрывается, точка не нужна
    if (!open) return;
    // поток может присылать точки чаще, чем просили, — сохраняем не чаще интервала
    if (_lastSaved != null && f.at.difference(_lastSaved!) < interval * 0.9) return;
    _lastSaved = f.at;
    lastFix = f.at;
    lastPlace = f;
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

  static int? _minutes(String? hhmm) {
    final p = hhmm?.split(':');
    if (p == null || p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  static DateTime _at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    outbox.removeListener(_changed);
    _fixes?.cancel();
    _status?.cancel();
    super.dispose();
  }
}
