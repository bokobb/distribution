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

/// Запросы к серверу дистрибуции (/api/mobile). Текст ошибки — от сервера, если он его прислал.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client}) : _http = client ?? http.Client();

  /// Адрес сервера без «/» в конце; меняется на экране входа.
  String baseUrl;
  final http.Client _http;

  static const timeout = Duration(seconds: 20);

  Future<Session> login(String login, String password) async {
    final json = await _post('/api/mobile/auth/login', {'login': login, 'password': password});
    return Session.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final http.Response r;
    try {
      r = await _http
          .post(Uri.parse('$baseUrl$path'),
              headers: {'Content-Type': 'application/json; charset=utf-8', 'Accept': 'application/json'},
              body: jsonEncode(body))
          .timeout(timeout);
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
    if (r.statusCode >= 200 && r.statusCode < 300 && data is Map<String, dynamic>) return data;
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
        >= 500 => 'Ошибка на сервере — попробуйте позже',
        _ => 'Сервер ответил ошибкой $status',
      };
}
