import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Кто вошёл в приложение: из ответа сервера на вход.
@immutable
class Session {
  const Session({
    required this.userId,
    required this.name,
    required this.role,
    this.company,
    this.phone,
    this.mustChangePassword = false,
  });

  final int userId;
  final String name;

  /// Роль на сервере: AGENT — торговый агент, EXPEDITOR — экспедитор. Остальные роли работают в веб-админке.
  final String role;
  final String? company;

  /// Телефон для входа: +77010000104; вошёл по логину — может не быть.
  final String? phone;

  /// Пароль временный (выдал директор) — сначала придумать свой.
  final bool mustChangePassword;

  bool get isAgent => role == 'AGENT';

  /// «Торговый представитель», «Экспедитор».
  String get roleTitle => isAgent ? 'Торговый представитель' : 'Экспедитор';

  /// Буквы для кружка: «Азамат К.» → «АК».
  String get initials {
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    return words.map((w) => w.characters.first.toUpperCase()).join();
  }

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        userId: (json['id'] as num).toInt(),
        name: json['name'] as String,
        role: json['role'] as String,
        company: json['company'] as String?,
        phone: json['phone'] as String?,
        mustChangePassword: json['mustChangePassword'] as bool? ?? false,
      );
}

/// Хранит на телефоне, кто вошёл, ключ устройства и адрес сервера. Ключ устройства — в защищённом хранилище
/// Android (по нему сервер выдаёт новый JWT без пароля), остальное — в обычных настройках.
class SessionStore {
  SessionStore({FlutterSecureStorage? secure}) : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static const _user = 'session.user';
  static const _server = 'server.url';
  static const _deviceToken = 'session.deviceToken';

  /// Адрес сервера по умолчанию: при сборке --dart-define=API_URL=https://…; для разработки — сервер на
  /// компьютере через `adb reverse tcp:8090 tcp:8090`.
  static const defaultServer = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8090');

  Future<Session?> load() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getInt('$_user.id');
    final name = p.getString('$_user.name');
    final role = p.getString('$_user.role');
    if (id == null || name == null || role == null) return null;
    return Session(
      userId: id,
      name: name,
      role: role,
      company: p.getString('$_user.company'),
      phone: p.getString('$_user.phone'),
      mustChangePassword: p.getBool('$_user.mustChange') ?? false,
    );
  }

  Future<void> save(Session s) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('$_user.id', s.userId);
    await p.setString('$_user.name', s.name);
    await p.setString('$_user.role', s.role);
    await p.setBool('$_user.mustChange', s.mustChangePassword);
    for (final (k, v) in [('company', s.company), ('phone', s.phone)]) {
      if (v == null) {
        await p.remove('$_user.$k');
      } else {
        await p.setString('$_user.$k', v);
      }
    }
  }

  Future<String?> deviceToken() => _secure.read(key: _deviceToken);

  Future<void> saveDeviceToken(String? token) =>
      token == null ? _secure.delete(key: _deviceToken) : _secure.write(key: _deviceToken, value: token);

  /// Забыть, кто вошёл, и ключ устройства. Адрес сервера остаётся.
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in ['id', 'name', 'role', 'company', 'phone', 'mustChange']) {
      await p.remove('$_user.$k');
    }
    await _secure.delete(key: _deviceToken);
  }

  Future<String> serverUrl() async =>
      (await SharedPreferences.getInstance()).getString(_server) ?? defaultServer;

  Future<void> setServerUrl(String url) async =>
      (await SharedPreferences.getInstance()).setString(_server, url);
}
