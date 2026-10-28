import 'package:flutter/material.dart';

import '../session.dart';
import '../theme.dart';

/// Главный экран по роли: у торгового агента — «Мой день» (маршрут на сегодня), у экспедитора — «Рейс».
/// Данные появятся с синхронизацией; пока экран пустой.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session, required this.onLogout});

  final Session session;
  final VoidCallback onLogout;

  Future<void> _confirmLogout(BuildContext context) async {
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
    if (ok == true) onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final agent = session.isAgent;
    final who = [session.name, if (session.company != null) session.company!].join(' · ');
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
            onSelected: (_) => _confirmLogout(context),
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
