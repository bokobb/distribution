import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'device.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/password_screen.dart';
import 'session.dart';
import 'theme.dart';

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
  runApp(DistributionApp(api: api, store: store, session: session));
}

class DistributionApp extends StatefulWidget {
  const DistributionApp({super.key, required this.api, required this.store, this.session});

  final ApiClient api;
  final SessionStore store;

  /// Кто вошёл в прошлый раз; null — показать вход.
  final Session? session;

  @override
  State<DistributionApp> createState() => _DistributionAppState();
}

class _DistributionAppState extends State<DistributionApp> {
  late Session? _session = widget.session;

  /// Почему снова вход: сервер закрыл вход на этом телефоне.
  String? _notice;

  @override
  void initState() {
    super.initState();
    widget.api.onSessionClosed = (message) => _forget(message);
  }

  Future<void> _signedIn(Session s) async {
    await widget.store.save(s);
    await widget.store.saveDeviceToken(widget.api.deviceToken);
    if (mounted) {
      setState(() {
        _session = s;
        _notice = null;
      });
    }
  }

  Future<void> _logout() async {
    await widget.api.logout();
    await _forget(null);
  }

  Future<void> _forget(String? notice) async {
    await widget.store.clear();
    if (mounted) {
      setState(() {
        _session = null;
        _notice = notice;
      });
    }
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
              : HomeScreen(api: widget.api, session: s, onSession: _signedIn, onLogout: _logout),
    );
  }
}
