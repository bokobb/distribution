import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../session.dart';

/// Ошибка, которую можно показать человеку как есть.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;

  /// Код ответа сервера; null — до сервера не достучались.
  final int? status;

  @override
  String toString() => message;
}

/// Вход на этом телефоне закрыт (вышли, сбросили пароль, отключили): нужен пароль.
class SessionClosedException extends ApiException {
  const SessionClosedException(super.message) : super(status: 401);
}

/// Запросы к серверу дистрибуции (/api/mobile). Вход как в CRM: пароль один раз — сервер выдаёт JWT на 12 часов
/// и ключ устройства; JWT истёк или сервер перезапускался — приложение само берёт новый по ключу.
/// Текст ошибки — от сервера, если он его прислал.
class ApiClient {
  ApiClient({required this.baseUrl, this.deviceToken, this.device, this.appVersion, http.Client? client})
      : _http = client ?? http.Client();

  /// Адрес сервера без «/» в конце; меняется на экране входа.
  String baseUrl;

  /// Ключ устройства; хранит его SessionStore, здесь — копия для запросов.
  String? deviceToken;

  /// Модель телефона и версия приложения — сервер пишет их в журнал входов.
  String? device;
  String? appVersion;

  /// Вход закрыт на сервере — приложение возвращается на экран входа.
  void Function(String message)? onSessionClosed;

  final http.Client _http;
  String? _jwt;
  Future<Session>? _refreshing;

  static const timeout = Duration(seconds: 20);

  Future<Session> login(String login, String password) async {
    final json = await _send('POST', '/api/mobile/auth/login',
        body: {'login': login, 'password': password, 'device': device, 'appVersion': appVersion});
    return _take(json);
  }

  /// Новый JWT по ключу устройства (несколько запросов сразу ждут одно продление).
  Future<Session> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<Session> _refresh() async {
    final key = deviceToken;
    if (key == null) throw _closed('Войдите с паролем');
    try {
      return _take(await _send('POST', '/api/mobile/auth/refresh', body: {'deviceToken': key}));
    } on ApiException catch (e) {
      if (e.status == 401) throw _closed(e.message);
      rethrow;
    }
  }

  Future<Session> me() async => Session.fromJson(await _authed('GET', '/api/mobile/me'));

  /// Свой пароль вместо временного; вход на остальных телефонах сотрудника закрывается.
  Future<Session> changePassword(String current, String password, String confirm) async =>
      Session.fromJson(await _authed('POST', '/api/mobile/auth/password',
          body: {'current': current, 'password': password, 'confirm': confirm, 'deviceToken': deviceToken}));

  /// «Выйти»: ключ закрывается на сервере. Нет сети — телефон просто забывает его.
  Future<void> logout() async {
    final key = deviceToken;
    deviceToken = null;
    _jwt = null;
    if (key == null) return;
    try {
      await _send('POST', '/api/mobile/auth/logout', body: {'deviceToken': key});
    } on ApiException {
      // без сети: ключ без дела закроется на сервере сам
    }
  }

  Future<Map<String, dynamic>> _authed(String method, String path, {Object? body}) async {
    if (_jwt == null) await refresh();
    try {
      return await _send(method, path, body: body, jwt: _jwt);
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      // JWT истёк или сервер перезапускался — новый по ключу и ещё раз
      await refresh();
      return _send(method, path, body: body, jwt: _jwt);
    }
  }

  Session _take(Map<String, dynamic> json) {
    _jwt = json['token'] as String?;
    deviceToken = json['deviceToken'] as String? ?? deviceToken;
    return Session.fromJson(json['user'] as Map<String, dynamic>);
  }

  SessionClosedException _closed(String message) {
    deviceToken = null;
    _jwt = null;
    onSessionClosed?.call(message);
    return SessionClosedException(message);
  }

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body, String? jwt}) async {
    final http.Response r;
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers['Accept'] = 'application/json';
      if (jwt != null) request.headers['Authorization'] = 'Bearer $jwt';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.body = jsonEncode(body);
      }
      r = await _http.send(request).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw const ApiException('Сервер не отвечает — проверьте интернет');
    } on http.ClientException {
      throw const ApiException('Нет связи с сервером');
    } on FormatException {
      throw const ApiException('Неверный адрес сервера');
    } on ArgumentError {
      throw const ApiException('Неверный адрес сервера');
    }
    final data = _json(r);
    if (r.statusCode >= 200 && r.statusCode < 300) return data is Map<String, dynamic> ? data : const {};
    final message = data is Map && data['message'] is String && (data['message'] as String).isNotEmpty
        ? data['message'] as String
        : _byStatus(r.statusCode);
    throw ApiException(message, status: r.statusCode);
  }

  static Object? _json(http.Response r) {
    if (r.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  static String _byStatus(int status) => switch (status) {
        401 => 'Неверный телефон или пароль',
        403 => 'Вход закрыт — обратитесь к директору',
        404 => 'Сервер не знает этот адрес — обновите приложение',
        429 => 'Много попыток — подождите минуту',
        >= 500 => 'Ошибка на сервере — попробуйте позже',
        _ => 'Сервер ответил ошибкой $status',
      };
}
