import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../workday.dart';

/// Шапка главного экрана: заголовок, кто вошёл; меню — «Обновить» (если есть) и «Выйти» с вопросом.
AppBar homeAppBar(BuildContext context,
        {required String title,
        required Session session,
        required Workday workday,
        VoidCallback? onRefresh,
        required VoidCallback onLogout}) =>
    AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text([session.name, if (session.company != null) session.company!].join(' · '),
              style: TextStyle(fontSize: 13, color: AppColors.cream.withValues(alpha: 0.7))),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Меню',
          onSelected: (v) => v == 'refresh' ? onRefresh?.call() : _confirmLogout(context, workday, onLogout),
          itemBuilder: (_) => [
            if (onRefresh != null) const PopupMenuItem(value: 'refresh', child: Text('Обновить')),
            const PopupMenuItem(value: 'logout', child: Text('Выйти')),
          ],
        ),
      ],
    );

/// Перед выходом: рабочий день закроется; неотправленное с телефона пропадёт — предупредить.
Future<void> _confirmLogout(BuildContext context, Workday workday, VoidCallback onLogout) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Выйти из приложения?'),
      content: Text([
        if (workday.open) 'Рабочий день будет закончен.',
        if (workday.unsent > 0)
          'На телефоне ждут отправки записей: ${workday.unsent}. После выхода они пропадут — лучше выйти, когда будет интернет.',
        'Чтобы войти снова, понадобится пароль.',
      ].join('\n\n')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Выйти')),
      ],
    ),
  );
  if (ok == true) onLogout();
}

/// Сверить с сервером, кто вошёл (имя, компания, роль могли поменяться). Нет сети — ничего не делать;
/// вход закрыт — приложение само вернётся на вход (ApiClient.onSessionClosed).
Future<void> checkSession(ApiClient api, Session session, ValueChanged<Session> onSession) async {
  try {
    final s = await api.me();
    if (s.name != session.name || s.company != session.company || s.role != session.role) onSession(s);
  } on ApiException {
    // без сети работаем с тем, что на телефоне
  }
}

/// Пустой экран с подсказкой.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.inkSoft),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(color: AppColors.inkSoft), textAlign: TextAlign.center),
          ],
        ),
      );
}
