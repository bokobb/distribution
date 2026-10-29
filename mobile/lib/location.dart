import 'dart:async';
import 'dart:ui' show Locale;

import 'package:battery_plus/battery_plus.dart';
import 'package:geocoding/geocoding.dart' show Geocoding;
import 'package:geolocator/geolocator.dart';

/// Где телефон: координаты, точность (м), когда снято.
class Fix {
  const Fix({required this.at, required this.lat, required this.lng, this.accuracy});

  final DateTime at;
  final double lat;
  final double lng;
  final int? accuracy;
}

/// Местоположение телефона и заряд батареи — отдельно от Workday, чтобы проверять его без телефона.
abstract class LocationSource {
  /// Доступ к местоположению: null — есть; иначе — что сделать человеку. Может спросить разрешение.
  Future<String?> ensureAccess();

  /// Разрешение уже есть — без вопросов человеку (для дня, который начинается сам).
  Future<bool> allowed();

  /// Местоположение (GPS) на телефоне включено сейчас.
  Future<bool> gpsOn();

  /// Точки раз в interval, пока на поток подписаны. На Android — фоновой службой с уведомлением
  /// «Рабочий день идёт»: точки идут и при погашенном экране.
  Stream<Fix> track(Duration interval);

  /// Где телефон сейчас — для отметки в магазине; не удалось за полминуты — null.
  Future<Fix?> current();

  /// Включено ли местоположение (GPS) на телефоне — при каждом изменении.
  Stream<bool> serviceStatus();

  /// Заряд батареи, %; не узнали — null.
  Future<int?> battery();

  /// Улица и дом у точки — для адреса нового магазина; нет сети или не нашлось — null.
  Future<String?> address(double lat, double lng);
}

/// «улица Абая, 41» из ответа геокодера: улица [road] и дом [house]; улицы нет — начало полного адреса [line]
/// («ул. Абая 41, Шымкент, Казахстан» → «ул. Абая 41»); дорога без названия — null.
String? streetAndHouse({String? road, String? house, String? line}) {
  bool unnamed(String s) => s.toLowerCase().contains('unnamed') || s.toLowerCase().contains('безымян');
  final r = road?.trim() ?? '', h = house?.trim() ?? '';
  if (r.isNotEmpty && !unnamed(r)) return h.isEmpty ? r : '$r, $h';
  final parts = (line ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty || unnamed(parts.first)) return null;
  // «41, мкр. Нурсат, …» — номер без улицы: берём и следующую часть
  if (!parts.first.contains(RegExp(r'[A-Za-zА-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі]')) && parts.length > 1) {
    return '${parts[1]}, ${parts.first}';
  }
  return parts.first;
}

/// Настоящий GPS (geolocator) и батарея (battery_plus).
class DeviceLocation implements LocationSource {
  @override
  Future<String?> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return 'Включите местоположение (GPS) на телефоне и нажмите ещё раз';
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return 'Разрешите приложению доступ к местоположению в настройках телефона';
    }
    if (p == LocationPermission.denied || p == LocationPermission.unableToDetermine) {
      return 'Без доступа к местоположению рабочий день не начать';
    }
    return null;
  }

  @override
  Future<bool> allowed() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> gpsOn() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return true; // не узнали — не пугаем
    }
  }

  @override
  Stream<Fix> track(Duration interval) => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          intervalDuration: interval,
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: 'Рабочий день идёт',
            notificationText: 'Приложение отмечает, где вы, раз в ${interval.inMinutes} мин.',
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      ).map(_fix);

  @override
  Future<Fix?> current() async {
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(accuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 30)));
      return _fix(p);
    } on TimeoutException {
      // в помещении спутники не видны — подойдёт недавняя точка
      final last = await Geolocator.getLastKnownPosition();
      return last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 2) ? _fix(last) : null;
    } on Exception {
      return null;
    }
  }

  static Fix _fix(Position p) =>
      Fix(at: p.timestamp.toLocal(), lat: p.latitude, lng: p.longitude, accuracy: p.accuracy.round());

  @override
  Stream<bool> serviceStatus() => Geolocator.getServiceStatusStream().map((s) => s == ServiceStatus.enabled);

  /// Геокодер телефона (на Android — службы Google, нужен интернет), названия по-русски.
  @override
  Future<String?> address(double lat, double lng) async {
    try {
      final found = await Geocoding(locale: const Locale('ru', 'KZ'))
          .placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 10));
      if (found.isEmpty) return null;
      final p = found.first;
      return streetAndHouse(road: p.thoroughfare, house: p.subThoroughfare, line: p.street);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int?> battery() async {
    try {
      return await Battery().batteryLevel;
    } catch (_) {
      return null;
    }
  }
}
