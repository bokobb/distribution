import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'app_lock.dart';
import 'camera.dart';
import 'data/agent_repo.dart';
import 'data/expeditor_repo.dart';
import 'data/local_store.dart';
import 'deliveries.dart';
import 'device.dart';
import 'location.dart';
import 'outbox.dart';
import 'screens/agent_home_screen.dart';
import 'screens/expeditor_home_screen.dart';
import 'screens/gps_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/password_screen.dart';
import 'session.dart';
import 'theme.dart';
import 'visits.dart';
import 'workday.dart';

/// Приложение «Юг Доставка» (проект «Дистрибуция») для торгового агента и экспедитора. Сервер — проект distribution, адреса /api/mobile.
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
  runApp(DistributionApp(
      api: api, store: store, local: await SqliteStore.open(), biometrics: DeviceBiometrics(), session: session));
}

class DistributionApp extends StatefulWidget {
  const DistributionApp(
      {super.key,
      required this.api,
      required this.store,
      required this.local,
      this.location,
      this.camera,
      this.biometrics,
      this.clock,
      this.session});

  final ApiClient api;
  final SessionStore store;

  /// Данные для работы без сети; при выходе стираются.
  final LocalStore local;

  /// GPS телефона; null — настоящий (в тестах — подставной).
  final LocationSource? location;

  /// Камера для фото полки; null — настоящая.
  final PhotoSource? camera;

  /// Отпечаток и лицо для замка; null — замка нет.
  final Biometrics? biometrics;

  /// Часы для рабочего времени; null — настоящие (в тестах — подставные).
  final DateTime Function()? clock;

  /// Кто вошёл в прошлый раз; null — показать вход.
  final Session? session;

  @override
  State<DistributionApp> createState() => _DistributionAppState();
}

class _DistributionAppState extends State<DistributionApp> with WidgetsBindingObserver {
  late Session? _session = widget.session;
  late final _agent = AgentRepo(widget.api, widget.local);
  late final _expeditor = ExpeditorRepo(widget.api, widget.local);
  late final _location = widget.location ?? DeviceLocation();
  late final _camera = widget.camera ?? DeviceCamera();
  late final _lock = AppLock(widget.biometrics ?? const NoBiometrics());

  /// Замок узнал, есть ли отпечаток, — до этого вошедшему показывается пустой экран, не приложение.
  bool _lockReady = false;

  /// Отправка на сервер, рабочий день с GPS, визиты и выдачи — пока вошёл сотрудник со своим паролем.
  Outbox? _outbox;
  Workday? _workday;
  VisitBook? _visits;
  DeliveryBook? _deliveries;

  /// Почему снова вход: сервер закрыл вход на этом телефоне.
  String? _notice;

  /// Спросить доступ к местоположению — один раз после входа, если его ещё нет.
  bool _askGps = false;
  static const _gpsAsked = 'gps.asked';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.api.onSessionClosed = (message) => _forget(message);
    final s = widget.session;
    if (s != null && !s.mustChangePassword) _startWorkday();
    _lock.addListener(_present);
    _lock.load().then((_) {
      // ещё не вошёл — замок не нужен: пароль он введёт сейчас
      if (_session == null) _lock.open();
      if (mounted) setState(() => _lockReady = true);
      _present();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _workday?.dispose();
    _visits?.dispose();
    _deliveries?.dispose();
    _outbox?.dispose();
    _lock
      ..removeListener(_present)
      ..dispose();
    super.dispose();
  }

  /// Вернулись в приложение — отправить накопленное (сеть могла появиться, пока оно было свёрнуто); свёрнуто было
  /// долго — замок; нет — в рабочее время день начинается сам.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _lock.shown();
        _present();
        _outbox?.flush();
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _lock.hidden();
        _workday?.away();
      default:
    }
  }

  /// Сотрудник в приложении — не под замком и не на вопросе о местоположении: в рабочее время день начинается сам.
  void _present() {
    if (_lockReady && !_lock.locked && !_askGps) _workday?.opened();
  }

  /// Доступа к местоположению нет и ещё не спрашивали — экран «Местоположение».
  Future<void> _checkGps() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_gpsAsked) == true || await _location.allowed()) return;
    if (mounted && _workday != null) setState(() => _askGps = true);
  }

  Future<void> _gpsDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_gpsAsked, true);
    if (mounted) setState(() => _askGps = false);
    _present();
  }

  /// Под замком «Назад» не листает экраны, которых не видно.
  @override
  Future<bool> didPopRoute() async => _lock.locked && _session != null;

  void _startWorkday() {
    final outbox = _outbox = Outbox(api: widget.api, store: widget.local)..start();
    _workday = Workday(outbox: outbox, store: widget.local, location: _location, clock: widget.clock)..restore();
    _visits = VisitBook(store: widget.local, outbox: outbox, location: _location, camera: _camera)..load();
    _deliveries = DeliveryBook(store: widget.local, outbox: outbox, location: _location, camera: _camera)..load();
    _checkGps();
  }

  Future<void> _stopWorkday() async {
    final w = _workday, v = _visits, d = _deliveries, o = _outbox;
    _workday = null;
    _visits = null;
    _deliveries = null;
    _outbox = null;
    await w?.stop();
    w?.dispose();
    v?.dispose();
    d?.dispose();
    o?.dispose();
  }

  /// Вошёл с паролем — замок не нужен.
  Future<void> _loggedIn(Session s) async {
    _lock.open();
    await _signedIn(s);
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
    _present();
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
    _askGps = false;
    await _stopWorkday();
    await widget.store.clear();
    await widget.local.clear();
    await _camera.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return MaterialApp(
      title: 'Юг Доставка',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      builder: (context, child) => AppLockScope(
        lock: _lock,
        child: ListenableBuilder(
          listenable: _lock,
          builder: (context, _) {
            final working = s != null && !s.mustChangePassword;
            final closed = working && (!_lockReady || _lock.locked);
            return Stack(children: [
              child!,
              if (working && _askGps) Positioned.fill(child: GpsScreen(location: _location, onDone: _gpsDone)),
              if (closed)
                Positioned.fill(
                  child: _lockReady
                      ? LockScreen(lock: _lock, name: s.name)
                      : const ColoredBox(color: AppColors.bg),
                ),
            ]);
          },
        ),
      ),
      home: s == null
          ? LoginScreen(api: widget.api, store: widget.store, notice: _notice, onLogin: _loggedIn)
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
                      repo: _expeditor,
                      session: s,
                      workday: _workday!,
                      deliveries: _deliveries!,
                      onSession: _signedIn,
                      onLogout: _logout),
    );
  }
}
