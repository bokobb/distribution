import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/delivery.dart';
import '../data/expeditor_data.dart';
import '../data/expeditor_repo.dart';
import '../deliveries.dart';
import '../format.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/workday_card.dart';
import '../workday.dart';
import '../widgets/layout.dart';
import 'day_summary_screen.dart';
import 'home_parts.dart';
import 'profile_screen.dart';
import 'stop_screen.dart';

/// Главный экран экспедитора: разделы «Доставки», «Касса» и «Профиль». «Доставки» — рейс на сегодня (и незакрытые прошлых дней) с точками по порядку, у каждой —
/// магазин, заказ, оплата и отметка выдачи (своя выдача видна сразу, до ответа сервера); отгруженное на завтра —
/// ниже, посмотреть заранее. Сразу показывает то, что на телефоне, и обновляет с сервера; нет связи — работает с
/// тем, что есть; выдачи и оплаты ушли на сервер — данные обновляются (долги магазинов).
class ExpeditorHomeScreen extends StatefulWidget {
  const ExpeditorHomeScreen(
      {super.key,
      required this.repo,
      required this.session,
      required this.workday,
      required this.deliveries,
      required this.onSession,
      required this.onLogout});

  final ExpeditorRepo repo;
  final Session session;
  final Workday workday;
  final DeliveryBook deliveries;
  final ValueChanged<Session> onSession;
  final VoidCallback onLogout;

  @override
  State<ExpeditorHomeScreen> createState() => _ExpeditorHomeScreenState();
}

class _ExpeditorHomeScreenState extends State<ExpeditorHomeScreen> {
  ExpeditorData? _data;

  /// Те же данные для «Кассы»: она обновляется вместе с «Доставками».
  final _shared = ValueNotifier<ExpeditorData?>(null);
  bool _loading = true;
  String? _syncError;
  late int _sent;

  @override
  void initState() {
    super.initState();
    _sent = widget.deliveries.outbox.expeditorSent;
    widget.deliveries.outbox.addListener(_onOutbox);
    _start();
  }

  @override
  void dispose() {
    widget.deliveries.outbox.removeListener(_onOutbox);
    _shared.dispose();
    super.dispose();
  }

  /// Выдачи или оплаты долга ушли на сервер — там поменялись статусы и долги.
  void _onOutbox() {
    final sent = widget.deliveries.outbox.expeditorSent;
    if (sent == _sent) return;
    _sent = sent;
    if (!_loading) _pull();
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
    _shared.value = data;
    if (data != null) widget.workday.setInterval(Duration(minutes: data.settings.gpsInterval));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final vehicle = data?.current.firstOrNull?.vehicle ?? data?.upcoming.firstOrNull?.vehicle;
    return HomeShell(
      tabs: const [
        TabItem('Доставки', Icons.local_shipping_outlined, Icons.local_shipping),
        TabItem('Касса', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
        TabItem('Профиль', Icons.person_outline, Icons.person),
      ],
      pages: [
        RefreshIndicator(
          onRefresh: _pull,
          child: ListenableBuilder(
            listenable: widget.deliveries,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                PageHeader(
                    title: 'Доставки', subtitle: [dayTitle(DateTime.now()), ?vehicle].join(' · ')),
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), child: WorkdayCard(workday: widget.workday)),
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
        ),
        DaySummaryView(data: _shared, deliveries: widget.deliveries),
        ProfileTab(
          api: widget.repo.api,
          session: widget.session,
          workday: widget.workday,
          vehicle: vehicle,
          dataLabel: 'Синхронизация',
          syncedAt: data?.syncedAt,
          onRefresh: _pull,
          outletNames: {
            for (final t in data?.trips ?? const <TripInfo>[])
              for (final st in t.stops) st.outlet.id: st.outlet.name
          },
          onSession: widget.onSession,
          onLogout: widget.onLogout,
        ),
      ],
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
              size: 16, color: _syncError != null ? AppColors.err : AppColors.text2),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: _syncError != null ? AppColors.err : AppColors.text2)),
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
              ahead
                  ? plural(t.stops.length, 'точка', 'точки', 'точек')
                  : 'пройдено ${widget.deliveries.doneIn(t)} из ${t.stops.length}',
            ].join(' · '),
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text2),
          ),
        ),
        for (final s in t.stops)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _StopTile(
              stop: s,
              local: widget.deliveries.of(s.order.id),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StopScreen(
                          stop: s,
                          trip: t,
                          data: data,
                          deliveries: widget.deliveries,
                          workday: widget.workday,
                          expeditor: widget.session.name))),
            ),
          ),
      ];
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.stop, this.local, required this.onTap});

  final Stop stop;

  /// Выдача на телефоне — пока сервер не ответил, точка показывается по ней.
  final Delivery? local;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = stop.outlet;
    final order = stop.order;
    final place = o.address ?? o.landmark;
    final d = order.done || local?.error != null ? null : local;
    final done = order.done || d != null;
    final refused = order.refused || d?.refused == true;
    final String? label = order.done
        ? order.statusLabel
        : d != null
            ? '${d.refused ? 'Отказ' : d.partial ? 'Выдано частично' : 'Выдано'}${d.sent ? '' : ' · ждёт отправки'}'
            : local?.error != null
                ? 'Выдача не принята сервером'
                : null;
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
                backgroundColor: !done
                    ? AppColors.fill
                    : refused
                        ? AppColors.err
                        : AppColors.ok,
                foregroundColor: done ? AppColors.card : AppColors.text,
                child: done
                    ? Icon(refused ? Icons.close : Icons.check, size: 18)
                    : Text('${stop.position + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    if (place != null) Text(place, style: const TextStyle(color: AppColors.text2)),
                    const SizedBox(height: 4),
                    Text('${order.number} · ${money(order.total)} · ${order.paymentLabel}'),
                    if (label != null)
                      Text(label, style: TextStyle(color: refused || !done ? AppColors.err : AppColors.ok)),
                    if (o.debt > 0)
                      Text('долг ${money(o.debt)}${o.overdue > 0 ? ', просрочено ${money(o.overdue)}' : ''}',
                          style: TextStyle(color: o.overdue > 0 ? AppColors.err : AppColors.text)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.text2),
            ],
          ),
        ),
      ),
    );
  }
}
