import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'data/agent_repo.dart';
import 'data/local_store.dart';
import 'device.dart';
import 'location.dart';
import 'screens/agent_home_screen.dart';
import 'screens/expeditor_home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/password_screen.dart';
import 'session.dart';
import 'theme.dart';
import 'workday.dart';

/// Приложение «Дистрибуция» для торгового агента и экспедитора. Сервер — проект distribution, адреса /api/mobile.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SessionStore();
  final session = await store.load();
  final about = await describeDevice();
  final api = ApiClient(
    baseUrl: await store.serverUrl(),
    deviceToken: await store.deviceToken(),
    device: about.device,
    appVersion: about.version,
  );
  runApp(DistributionApp(api: api, store: store, local: await SqliteStore.open(), session: session));
}

class DistributionApp extends StatefulWidget {
  const DistributionApp(
      {super.key, required this.api, required this.store, required this.local, this.location, this.session});

  final ApiClient api;
  final SessionStore store;

  /// Данные для работы без сети; при выходе стираются.
  final LocalStore local;

  /// GPS телефона; null — настоящий (в тестах — подставной).
  final LocationSource? location;

  /// Кто вошёл в прошлый раз; null — показать вход.
  final Session? session;

  @override
  State<DistributionApp> createState() => _DistributionAppState();
}

class _DistributionAppState extends State<DistributionApp> {
  late Session? _session = widget.session;
  late final _agent = AgentRepo(widget.api, widget.local);

  /// Рабочий день и GPS — пока вошёл сотрудник со своим паролем.
  Workday? _workday;

  /// Почему снова вход: сервер закрыл вход на этом телефоне.
  String? _notice;

  @override
  void initState() {
    super.initState();
    widget.api.onSessionClosed = (message) => _forget(message);
    final s = widget.session;
    if (s != null && !s.mustChangePassword) _startWorkday();
  }

  void _startWorkday() {
    _workday = Workday(api: widget.api, store: widget.local, location: widget.location ?? DeviceLocation())..restore();
  }

  Future<void> _stopWorkday() async {
    final w = _workday;
    _workday = null;
    await w?.stop();
    w?.dispose();
  }

  Future<void> _signedIn(Session s) async {
    await widget.store.save(s);
    await widget.store.saveDeviceToken(widget.api.deviceToken);
    if (!s.mustChangePassword && _workday == null) _startWorkday();
    if (mounted) {
      setState(() {
        _session = s;
        _notice = null;
      });
    }
  }

  /// «Выйти»: открытый рабочий день закрывается, накопленное пробуем отправить, ключ закрывается на сервере.
  Future<void> _logout() async {
    await _workday?.end();
    await _workday?.flush();
    await _stopWorkday();
    await widget.api.logout();
    await _forget(null);
  }

  Future<void> _forget(String? notice) async {
    // вход уже закрыт (другой запрос успел раньше) — подсказку первого не затираем
    if (_session == null) return;
    setState(() {
      _session = null;
      _notice = notice;
    });
    await _stopWorkday();
    await widget.store.clear();
    await widget.local.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return MaterialApp(
      title: 'Дистрибуция',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: s == null
          ? LoginScreen(api: widget.api, store: widget.store, notice: _notice, onLogin: _signedIn)
          : s.mustChangePassword
              ? PasswordScreen(api: widget.api, session: s, onDone: _signedIn, onLogout: _logout)
              : s.isAgent
                  ? AgentHomeScreen(
                      repo: _agent, session: s, workday: _workday!, onSession: _signedIn, onLogout: _logout)
                  : ExpeditorHomeScreen(
                      api: widget.api, session: s, workday: _workday!, onSession: _signedIn, onLogout: _logout),
    );
  }
}
