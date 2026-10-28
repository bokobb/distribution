import 'package:battery_plus/battery_plus.dart';
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
  /// Доступ к местоположению: null — есть; иначе — что сделать человеку.
  Future<String?> ensureAccess();

  /// Точки раз в interval, пока на поток подписаны. На Android — фоновой службой с уведомлением
  /// «Рабочий день идёт»: точки идут и при погашенном экране.
  Stream<Fix> track(Duration interval);

  /// Включено ли местоположение (GPS) на телефоне — при каждом изменении.
  Stream<bool> serviceStatus();

  /// Заряд батареи, %; не узнали — null.
  Future<int?> battery();
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
      ).map((p) => Fix(at: p.timestamp.toLocal(), lat: p.latitude, lng: p.longitude, accuracy: p.accuracy.round()));

  @override
  Stream<bool> serviceStatus() => Geolocator.getServiceStatusStream().map((s) => s == ServiceStatus.enabled);

  @override
  Future<int?> battery() async {
    try {
      return await Battery().batteryLevel;
    } catch (_) {
      return null;
    }
  }
}
