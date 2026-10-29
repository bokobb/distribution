import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../session.dart';
import '../theme.dart';
import '../workday.dart';

/// Перед выходом: рабочий день закроется; неотправленное с телефона пропадёт — предупредить.
Future<void> confirmLogout(BuildContext context, Workday workday, VoidCallback onLogout) async {
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
    if (s.name != session.name || s.company != session.company || s.role != session.role || s.phone != session.phone) {
      onSession(s);
    }
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
            Icon(icon, size: 48, color: AppColors.text2),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(color: AppColors.text2), textAlign: TextAlign.center),
          ],
        ),
      );
}
