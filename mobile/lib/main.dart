import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'camera.dart';
import 'data/agent_repo.dart';
import 'data/local_store.dart';
import 'device.dart';
import 'location.dart';
import 'outbox.dart';
import 'screens/agent_home_screen.dart';
import 'screens/expeditor_home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/password_screen.dart';
import 'session.dart';
import 'theme.dart';
import 'visits.dart';
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
      {super.key,
      required this.api,
      required this.store,
      required this.local,
      this.location,
      this.camera,
      this.session});

  final ApiClient api;
  final SessionStore store;

  /// Данные для работы без сети; при выходе стираются.
  final LocalStore local;

  /// GPS телефона; null — настоящий (в тестах — подставной).
  final LocationSource? location;

  /// Камера для фото полки; null — настоящая.
  final PhotoSource? camera;

  /// Кто вошёл в прошлый раз; null — показать вход.
  final Session? session;

  @override
  State<DistributionApp> createState() => _DistributionAppState();
}

class _DistributionAppState extends State<DistributionApp> with WidgetsBindingObserver {
  late Session? _session = widget.session;
  late final _agent = AgentRepo(widget.api, widget.local);
  late final _location = widget.location ?? DeviceLocation();
  late final _camera = widget.camera ?? DeviceCamera();

  /// Отправка на сервер, рабочий день с GPS и визиты — пока вошёл сотрудник со своим паролем.
  Outbox? _outbox;
  Workday? _workday;
  VisitBook? _visits;

  /// Почему снова вход: сервер закрыл вход на этом телефоне.
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.api.onSessionClosed = (message) => _forget(message);
    final s = widget.session;
    if (s != null && !s.mustChangePassword) _startWorkday();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _workday?.dispose();
    _visits?.dispose();
    _outbox?.dispose();
    super.dispose();
  }

  /// Вернулись в приложение — отправить накопленное (сеть могла появиться, пока оно было свёрнуто).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _outbox?.flush();
  }

  void _startWorkday() {
    final outbox = _outbox = Outbox(api: widget.api, store: widget.local)..start();
    _workday = Workday(outbox: outbox, store: widget.local, location: _location)..restore();
    _visits = VisitBook(store: widget.local, outbox: outbox, location: _location, camera: _camera)..load();
  }

  Future<void> _stopWorkday() async {
    final w = _workday, v = _visits, o = _outbox;
    _workday = null;
    _visits = null;
    _outbox = null;
    await w?.stop();
    w?.dispose();
    v?.dispose();
    o?.dispose();
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
    await _camera.clear();
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
                      repo: _agent,
                      session: s,
                      workday: _workday!,
                      visits: _visits!,
                      onSession: _signedIn,
                      onLogout: _logout)
                  : ExpeditorHomeScreen(
                      api: widget.api, session: s, workday: _workday!, onSession: _signedIn, onLogout: _logout),
    );
  }
}
