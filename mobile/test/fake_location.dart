import 'dart:async';

import 'package:distribution_mobile/location.dart';

/// GPS для тестов: точки и включение GPS подаются вручную.
class FakeLocation implements LocationSource {
  /// Что ответить на «Начать день»: null — доступ есть.
  String? problem;
  final fixes = StreamController<Fix>.broadcast();
  final status = StreamController<bool>.broadcast();
  Duration? interval;
  int tracking = 0;

  /// Где телефон сейчас (у магазинов из sampleAgentData); null — GPS не ответил.
  Fix? here = Fix(at: DateTime(2026, 10, 28, 10), lat: 42.3, lng: 69.6, accuracy: 12);

  /// Местоположение на телефоне включено.
  bool on = true;

  /// Сколько раз спросили разрешение.
  int asked = 0;

  @override
  Future<String?> ensureAccess() async {
    asked++;
    return problem;
  }

  @override
  Future<bool> allowed() async => problem == null;

  @override
  Future<bool> gpsOn() async => on;

  @override
  Stream<Fix> track(Duration interval) {
    this.interval = interval;
    tracking++;
    return fixes.stream;
  }

  @override
  Future<Fix?> current() async => here;

  @override
  Stream<bool> serviceStatus() => status.stream;

  @override
  Future<int?> battery() async => 77;

  /// Что ответит геокодер; null — не нашёл или нет сети.
  String? street = 'улица Абая, 7';

  /// Точки, для которых спросили адрес.
  final addressed = <(double, double)>[];

  @override
  Future<String?> address(double lat, double lng) async {
    addressed.add((lat, lng));
    return street;
  }

  void fix(DateTime at, {double lat = 42.3, double lng = 69.6}) => fixes.add(Fix(at: at, lat: lat, lng: lng, accuracy: 10));
}
