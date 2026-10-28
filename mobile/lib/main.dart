import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'session.dart';
import 'theme.dart';

/// Приложение «Дистрибуция» для торгового агента и экспедитора. Сервер — проект distribution, адреса /api/mobile.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SessionStore();
  final session = await store.load();
  final api = ApiClient(baseUrl: await store.serverUrl());
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

  Future<void> _logout() async {
    await widget.store.clear();
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return MaterialApp(
      title: 'Дистрибуция',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: s == null
          ? LoginScreen(api: widget.api, store: widget.store, onLogin: (s) => setState(() => _session = s))
          : HomeScreen(session: s, onLogout: _logout),
    );
  }
}
