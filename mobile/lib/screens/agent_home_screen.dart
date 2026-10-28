import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/agent_data.dart';
import '../data/agent_repo.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/workday_card.dart';
import '../workday.dart';
import 'home_parts.dart';
import 'outlet_screen.dart';

/// «Мой день» торгового агента: маршруты выбранного дня (по умолчанию сегодня) и магазины по порядку обхода
/// с долгами. Сразу показывает то, что на телефоне, и обновляет с сервера; нет связи — работает с тем, что есть.
class AgentHomeScreen extends StatefulWidget {
  const AgentHomeScreen(
      {super.key,
      required this.repo,
      required this.session,
      required this.workday,
      required this.onSession,
      required this.onLogout});

  final AgentRepo repo;
  final Session session;
  final Workday workday;
  final ValueChanged<Session> onSession;
  final VoidCallback onLogout;

  @override
  State<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends State<AgentHomeScreen> {
  AgentData? _data;
  bool _loading = true;
  String? _syncError;
  int _weekday = DateTime.now().weekday;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final local = await widget.repo.local();
    if (mounted) _show(local);
    await _pull();
    if (mounted) checkSession(widget.repo.api, widget.session, widget.onSession);
  }

  Future<void> _pull() async {
    setState(() => _loading = true);
    try {
      final data = await widget.repo.pull();
      if (mounted) {
        _show(data);
        setState(() => _syncError = null);
      }
    } on SessionClosedException {
      // приложение уже вернулось на вход
    } on ApiException catch (e) {
      if (mounted) setState(() => _syncError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Данные на экран; интервал GPS — из настроек компании.
  void _show(AgentData? data) {
    setState(() => _data = data);
    if (data != null) widget.workday.setInterval(Duration(minutes: data.settings.gpsInterval));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: homeAppBar(context,
          title: 'Мой день',
          session: widget.session,
          workday: widget.workday,
          onRefresh: _pull,
          onLogout: widget.onLogout),
      body: RefreshIndicator(
        onRefresh: _pull,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: WorkdayCard(workday: widget.workday)),
            _days(),
            _status(data),
            if (data == null && !_loading)
              const EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Нет данных',
                text: 'Подключитесь к интернету и потяните экран вниз, чтобы получить маршруты и товары.',
              ),
            if (data != null) ..._routes(data),
          ],
        ),
      ),
    );
  }

  Widget _days() {
    final today = DateTime.now().weekday;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        children: [
          for (var d = 1; d <= 7; d++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(d == today ? '${weekdaysShort[d - 1]} · сегодня' : weekdaysShort[d - 1]),
                selected: _weekday == d,
                onSelected: (_) => setState(() => _weekday = d),
              ),
            ),
        ],
      ),
    );
  }

  Widget _status(AgentData? data) {
    final String text;
    if (_loading) {
      text = 'Обновляю…';
    } else if (_syncError != null) {
      text = data == null ? _syncError! : '$_syncError. Данные ${when(data.syncedAt)}';
    } else if (data != null) {
      text = 'Обновлено ${when(data.syncedAt)}';
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Icon(_syncError != null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
              size: 16, color: _syncError != null ? AppColors.crimson : AppColors.inkSoft),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: _syncError != null ? AppColors.crimson : AppColors.inkSoft)),
          ),
        ],
      ),
    );
  }

  List<Widget> _routes(AgentData data) {
    final routes = data.routesOn(_weekday);
    if (routes.isEmpty) {
      return const [
        EmptyState(icon: Icons.event_busy_outlined, title: 'Маршрутов нет', text: 'В этот день по вашим маршрутам обхода нет.'),
      ];
    }
    return [
      for (final r in routes) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            [r.name, if (r.region != null) r.region!, plural(data.outletsOf(r).length, 'магазин', 'магазина', 'магазинов')]
                .join(' · '),
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft),
          ),
        ),
        for (final (i, o) in data.outletsOf(r).indexed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _OutletTile(
              number: i + 1,
              outlet: o,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OutletScreen(outlet: o, data: data))),
            ),
          ),
      ],
    ];
  }
}

class _OutletTile extends StatelessWidget {
  const _OutletTile({required this.number, required this.outlet, required this.onTap});

  final int number;
  final Outlet outlet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = outlet;
    final place = o.address ?? o.landmark;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.paperDeep,
                foregroundColor: AppColors.ink,
                child: Text('$number', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    if (place != null) Text(place, style: const TextStyle(color: AppColors.inkSoft)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      children: [
                        if (o.pending) const Text('на проверке', style: TextStyle(color: AppColors.inkSoft)),
                        if (o.debt > 0)
                          Text('долг ${money(o.debt)}',
                              style: TextStyle(color: o.overdue > 0 || o.overLimit ? AppColors.crimson : AppColors.ink)),
                        if (o.overdue > 0)
                          Text('просрочено ${money(o.overdue)}', style: const TextStyle(color: AppColors.crimson)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
