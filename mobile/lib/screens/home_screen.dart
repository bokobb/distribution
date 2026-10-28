import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';

/// Главный экран по роли: у торгового агента — «Мой день» (маршрут на сегодня), у экспедитора — «Рейс».
/// При открытии сверяется с сервером, кто вошёл (имя и компания могли поменяться); без сети — работает
/// с тем, что на телефоне. Данные появятся с синхронизацией; пока экран пустой.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.session, required this.onSession, required this.onLogout});

  final ApiClient api;
  final Session session;
  final ValueChanged<Session> onSession;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final s = await widget.api.me();
      if (mounted && (s.name != widget.session.name || s.company != widget.session.company || s.role != widget.session.role)) {
        widget.onSession(s);
      }
    } on ApiException {
      // нет сети — работаем с тем, что на телефоне; вход закрыт — приложение само вернётся на вход
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Выйти из приложения?'),
        content: const Text('Чтобы войти снова, понадобится пароль.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok == true) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final agent = s.isAgent;
    final who = [s.name, if (s.company != null) s.company!].join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(agent ? 'Мой день' : 'Рейс', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(who, style: TextStyle(fontSize: 13, color: AppColors.cream.withValues(alpha: 0.7))),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Меню',
            onSelected: (_) => _confirmLogout(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'logout', child: Text('Выйти'))],
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(agent ? Icons.route_outlined : Icons.local_shipping_outlined, size: 48, color: AppColors.inkSoft),
              const SizedBox(height: 16),
              Text(agent ? 'Маршрут на сегодня' : 'Рейс на сегодня',
                  style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Появится здесь, когда приложение получит данные с сервера.',
                  style: TextStyle(color: AppColors.inkSoft), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
