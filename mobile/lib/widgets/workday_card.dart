import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import '../workday.dart';
import 'message_box.dart';

/// Рабочий день на главном экране — только когда нужно действие: день не начат («Начать рабочий день») или GPS
/// выключен на телефоне. Идёт — ничего не показывает: время начала и GPS — в «Профиле».
class WorkdayCard extends StatelessWidget {
  const WorkdayCard({super.key, required this.workday});

  final Workday workday;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: workday,
        builder: (context, _) {
          final w = workday;
          if (w.open) {
            return w.gpsOff
                ? const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: MessageBox.error('Местоположение выключено — включите GPS на телефоне'),
                  )
                : const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(w.endedAt != null ? 'День закончен в ${time(w.endedAt!)}' : 'Рабочий день не начат',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    const Text('Начните день — приложение будет отмечать путь и визиты.',
                        style: TextStyle(color: AppColors.text2)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: w.busy ? null : () => startWorkday(context, workday),
                      child: const Text('Начать рабочий день'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// «Начать день»: не получилось (нет разрешения на местоположение и т. п.) — подсказка внизу экрана.
Future<void> startWorkday(BuildContext context, Workday workday) async {
  final problem = await workday.start();
  if (problem != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
  }
}

/// «Закончить день» — с вопросом.
Future<void> endWorkday(BuildContext context, Workday workday) async {
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
