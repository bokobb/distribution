import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Кто вошёл в приложение: из ответа сервера на вход. Ключи доступа (токены) добавятся вместе со входом
/// на сервере (/api/mobile/auth).
@immutable
class Session {
  const Session({required this.userId, required this.name, required this.role, this.company});

  final int userId;
  final String name;

  /// Роль на сервере: AGENT — торговый агент, EXPEDITOR — экспедитор. Остальные роли работают в веб-админке.
  final String role;
  final String? company;

  bool get isAgent => role == 'AGENT';
  bool get isExpeditor => role == 'EXPEDITOR';
  bool get isFieldRole => isAgent || isExpeditor;

  String get roleLabel => isAgent ? 'Торговый агент' : isExpeditor ? 'Экспедитор' : role;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        userId: (json['id'] as num).toInt(),
        name: json['name'] as String,
        role: json['role'] as String,
        company: json['company'] as String?,
      );
}

/// Хранит на телефоне, кто вошёл, и адрес сервера.
class SessionStore {
  static const _user = 'session.user';
  static const _server = 'server.url';

  /// Адрес сервера по умолчанию: при сборке --dart-define=API_URL=https://…; для разработки — сервер на
  /// компьютере через `adb reverse tcp:8090 tcp:8090`.
  static const defaultServer = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8090');

  Future<Session?> load() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getInt('$_user.id');
    final name = p.getString('$_user.name');
    final role = p.getString('$_user.role');
    if (id == null || name == null || role == null) return null;
    return Session(userId: id, name: name, role: role, company: p.getString('$_user.company'));
  }

  Future<void> save(Session s) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('$_user.id', s.userId);
    await p.setString('$_user.name', s.name);
    await p.setString('$_user.role', s.role);
    if (s.company == null) {
      await p.remove('$_user.company');
    } else {
      await p.setString('$_user.company', s.company!);
    }
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in ['id', 'name', 'role', 'company']) {
      await p.remove('$_user.$k');
    }
  }

  Future<String> serverUrl() async =>
      (await SharedPreferences.getInstance()).getString(_server) ?? defaultServer;

  Future<void> setServerUrl(String url) async =>
      (await SharedPreferences.getInstance()).setString(_server, url);
}
