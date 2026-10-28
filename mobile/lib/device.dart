import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Модель телефона («Samsung SM-A515F · Android 13») и версия приложения («1.0.0+1») — сервер пишет их в
/// журнал входов. Не удалось узнать — null.
Future<({String? device, String? version})> describeDevice() async {
  String? device;
  String? version;
  try {
    final a = await DeviceInfoPlugin().androidInfo;
    final maker = a.manufacturer.isEmpty ? '' : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
    device = '$maker${a.model} · Android ${a.version.release}';
  } catch (_) {
    // не Android или плагин недоступен — без модели
  }
  try {
    final p = await PackageInfo.fromPlatform();
    version = '${p.version}+${p.buildNumber}';
  } catch (_) {
    // без версии
  }
  return (device: device, version: version);
}
