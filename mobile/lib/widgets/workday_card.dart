import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import '../workday.dart';

/// Рабочий день на главном экране: «Начать день» или с какого времени идёт, последняя точка GPS, сколько ждёт
/// отправки, «Закончить день».
class WorkdayCard extends StatelessWidget {
  const WorkdayCard({super.key, required this.workday});

  final Workday workday;

  Future<void> _start(BuildContext context) async {
    final problem = await workday.start();
    if (problem != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _end(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Закончить рабочий день?'),
        content: const Text('Приложение перестанет отмечать, где вы.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Закончить')),
        ],
      ),
    );
    if (ok == true) await workday.end();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: workday,
        builder: (context, _) {
          final w = workday;
          final lines = <(String, bool)>[
            if (w.open) (w.lastFix == null ? 'GPS ещё не отметился' : 'GPS: последняя точка в ${time(w.lastFix!)}', false),
            if (w.gpsOff) ('Местоположение выключено — включите GPS на телефоне', true),
            if (w.unsent > 0) ('Ждут отправки: ${w.unsent} — уйдут, когда будет интернет', false),
          ];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(w.open ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          size: 18, color: w.open ? AppColors.ok : AppColors.inkSoft),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          w.open
                              ? 'Рабочий день с ${time(w.startedAt!)}'
                              : w.endedAt != null
                                  ? 'День закончен в ${time(w.endedAt!)}'
                                  : 'Рабочий день не начат',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  for (final (text, alarm) in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 26),
                      child: Text(text, style: TextStyle(color: alarm ? AppColors.crimson : AppColors.inkSoft)),
                    ),
                  const SizedBox(height: 12),
                  if (w.open)
                    OutlinedButton(onPressed: () => _end(context), child: const Text('Закончить день'))
                  else
                    FilledButton(
                      onPressed: w.busy ? null : () => _start(context),
                      child: const Text('Начать день'),
                    ),
                ],
              ),
            ),
          );
        },
      );
}
