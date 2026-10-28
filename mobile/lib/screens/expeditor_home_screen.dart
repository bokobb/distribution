import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/expeditor_data.dart';
import '../data/expeditor_repo.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/workday_card.dart';
import '../workday.dart';
import 'home_parts.dart';
import 'stop_screen.dart';

/// Главный экран экспедитора — «Рейс»: рейс на сегодня (и незакрытые прошлых дней) с точками по порядку, у каждой —
/// магазин, заказ, оплата и отметка выдачи; отгруженное на завтра — ниже, посмотреть заранее. Сразу показывает
/// то, что на телефоне, и обновляет с сервера; нет связи — работает с тем, что есть.
class ExpeditorHomeScreen extends StatefulWidget {
  const ExpeditorHomeScreen(
      {super.key,
      required this.repo,
      required this.session,
      required this.workday,
      required this.onSession,
      required this.onLogout});

  final ExpeditorRepo repo;
  final Session session;
  final Workday workday;
  final ValueChanged<Session> onSession;
  final VoidCallback onLogout;

  @override
  State<ExpeditorHomeScreen> createState() => _ExpeditorHomeScreenState();
}

class _ExpeditorHomeScreenState extends State<ExpeditorHomeScreen> {
  ExpeditorData? _data;
  bool _loading = true;
  String? _syncError;

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

  void _show(ExpeditorData? data) {
    setState(() => _data = data);
    if (data != null) widget.workday.setInterval(Duration(minutes: data.settings.gpsInterval));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: homeAppBar(context,
          title: 'Рейс', session: widget.session, workday: widget.workday, onRefresh: _pull, onLogout: widget.onLogout),
      body: RefreshIndicator(
        onRefresh: _pull,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: WorkdayCard(workday: widget.workday)),
            _status(data),
            if (data == null && !_loading)
              const EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Нет данных',
                text: 'Подключитесь к интернету и потяните экран вниз, чтобы получить рейс.',
              ),
            if (data != null && data.current.isEmpty)
              const EmptyState(
                icon: Icons.local_shipping_outlined,
                title: 'Рейса на сегодня нет',
                text: 'Когда вам отгрузят заказы, они появятся здесь. Потяните экран вниз, чтобы обновить.',
              ),
            if (data != null) ...[
              for (final t in data.current) ..._trip(data, t),
              for (final t in data.upcoming) ..._trip(data, t, ahead: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _status(ExpeditorData? data) {
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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

  List<Widget> _trip(ExpeditorData data, TripInfo t, {bool ahead = false}) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            [
              ahead ? 'На ${date(t.date)}' : (t.date.isBefore(data.date) ? 'С ${date(t.date)}' : 'Сегодня'),
              t.number,
              if (t.vehicle != null) t.vehicle!,
              ahead ? plural(t.stops.length, 'точка', 'точки', 'точек') : 'пройдено ${t.done} из ${t.stops.length}',
            ].join(' · '),
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft),
          ),
        ),
        for (final s in t.stops)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _StopTile(
              stop: s,
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => StopScreen(stop: s, trip: t, data: data))),
            ),
          ),
      ];
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.stop, required this.onTap});

  final Stop stop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = stop.outlet;
    final order = stop.order;
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
                backgroundColor: !order.done
                    ? AppColors.paperDeep
                    : order.refused
                        ? AppColors.crimson
                        : AppColors.ok,
                foregroundColor: order.done ? AppColors.cream : AppColors.ink,
                child: order.done
                    ? Icon(order.refused ? Icons.close : Icons.check, size: 18)
                    : Text('${stop.position + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    if (place != null) Text(place, style: const TextStyle(color: AppColors.inkSoft)),
                    const SizedBox(height: 4),
                    Text('${order.number} · ${money(order.total)} · ${order.paymentLabel}'),
                    if (order.done)
                      Text(order.statusLabel,
                          style: TextStyle(color: order.refused ? AppColors.crimson : AppColors.ok)),
                    if (o.debt > 0)
                      Text('долг ${money(o.debt)}${o.overdue > 0 ? ', просрочено ${money(o.overdue)}' : ''}',
                          style: TextStyle(color: o.overdue > 0 ? AppColors.crimson : AppColors.ink)),
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
