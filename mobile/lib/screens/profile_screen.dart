import 'package:flutter/material.dart';

import '../app_lock.dart';
import '../api/api_client.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/layout.dart';
import '../widgets/message_box.dart';
import '../widgets/workday_card.dart';
import '../workday.dart';
import 'home_parts.dart';
import 'password_screen.dart';
import 'send_screen.dart';

/// «Профиль» торгового и экспедитора: кто вошёл, что с отправкой (плашка ведёт на «Отправку»), машина, рабочий день,
/// GPS, когда обновлены данные (нажать — обновить), смена пароля, начать или закончить день, выход.
/// rows — строки роли сверху карточки («Мой путь сегодня»); dataLabel — «Синхронизация» или «Каталог и цены».
class ProfileTab extends StatelessWidget {
  const ProfileTab(
      {super.key,
      required this.api,
      required this.session,
      required this.workday,
      required this.dataLabel,
      this.syncedAt,
      this.onRefresh,
      this.vehicle,
      this.rows = const [],
      this.outletNames = const {},
      required this.onSession,
      required this.onLogout});

  final ApiClient api;
  final Session session;
  final Workday workday;
  final String dataLabel;

  /// Когда данные последний раз пришли с сервера.
  final DateTime? syncedAt;
  final Future<void> Function()? onRefresh;
  final String? vehicle;
  final List<Widget> rows;

  /// Названия магазинов для «Отправки».
  final Map<int, String> outletNames;
  final ValueChanged<Session> onSession;
  final VoidCallback onLogout;

  void _send(BuildContext context) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => SendScreen(outbox: workday.outbox, outletNames: outletNames)));

  Future<void> _password(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (c) => PasswordScreen(
              api: api,
              session: session,
              change: true,
              onLogout: onLogout,
              onDone: (s) {
                Navigator.pop(c);
                onSession(s);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пароль сменён')));
              })));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lock = AppLockScope.maybeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([workday, workday.outbox]),
      builder: (context, _) {
        final w = workday;
        final synced = syncedAt;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Профиль', style: text.headlineMedium),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.accentSoft,
                      foregroundColor: AppColors.accentPressed,
                      child: Text(session.initials, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(session.name, style: text.titleLarge),
                          Text([session.roleTitle, if (session.company != null) session.company!].join(' · '),
                              style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                          if (session.phone != null)
                            Text(phoneText(session.phone!), style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _sendState(context),
            const SizedBox(height: 12),
            GroupCard(children: [
              ...rows,
              if (vehicle != null) InfoRow(label: 'Машина', value: vehicle),
              InfoRow(
                label: 'Рабочий день',
                value: w.open
                    ? 'с ${time(w.startedAt!)}'
                    : w.endedAt != null
                        ? 'закончен в ${time(w.endedAt!)}'
                        : 'не начат',
              ),
              InfoRow(
                label: 'GPS',
                dot: w.gpsOff ? AppColors.err : w.open ? AppColors.ok : AppColors.icon,
                value: w.gpsOff
                    ? 'выключен на телефоне'
                    : !w.open
                        ? 'не пишется'
                        : session.isAgent
                            ? 'включён · путь пишется'
                            : 'включён',
              ),
              InfoRow(
                label: dataLabel,
                value: synced == null ? 'нет данных' : _synced(synced),
                onTap: onRefresh == null ? null : () => onRefresh!(),
              ),
            ]),
            const SizedBox(height: 12),
            GroupCard(children: [
              if (lock != null && lock.available)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                    child: Row(children: [
                      Expanded(child: Text('Вход ${lock.by}')),
                      Switch(value: lock.enabled, onChanged: lock.setEnabled),
                    ]),
                  ),
                ),
              InfoRow(label: 'Сменить пароль', onTap: () => _password(context)),
            ]),
            const SizedBox(height: 16),
            if (w.open)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.errBg, foregroundColor: const Color(0xFFB0261A)),
                onPressed: () => endWorkday(context, w),
                child: const Text('Закончить рабочий день'),
              )
            else
              FilledButton(
                onPressed: w.busy ? null : () => startWorkday(context, w),
                child: const Text('Начать рабочий день'),
              ),
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.text2),
              onPressed: () => confirmLogout(context, w, onLogout),
              child: const Text('Выйти из аккаунта'),
            ),
          ],
        );
      },
    );
  }

  /// «в 11:02» сегодня, иначе «28.10 в 18:02».
  static String _synced(DateTime t) {
    final s = when(t);
    return s.startsWith('сегодня ') ? s.substring('сегодня '.length) : s;
  }

  Widget _sendState(BuildContext context) {
    final o = workday.outbox;
    final waiting = plural(o.unsent, 'запись ждёт', 'записи ждут', 'записей ждут');
    if (o.unsent == 0) {
      final last = o.lastOk ?? syncedAt;
      return MessageBox.ok(last == null ? 'Всё отправлено' : 'Всё отправлено · последняя синхронизация ${_synced(last)}',
          onTap: () => _send(context));
    }
    if (o.sending) return MessageBox.info('Отправляю: $waiting отправки…', onTap: () => _send(context));
    if (o.lastError != null) {
      return MessageBox.warn('$waiting отправки и уйдут сами, когда появится связь.',
          title: 'Нет сети.', onTap: () => _send(context));
    }
    return MessageBox.warn('$waiting отправки.', onTap: () => _send(context));
  }
}
