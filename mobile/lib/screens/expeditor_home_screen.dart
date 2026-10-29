import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/expeditor_data.dart';
import '../data/expeditor_repo.dart';
import '../deliveries.dart';
import '../session.dart';
import '../workday.dart';
import '../widgets/layout.dart';
import 'day_summary_screen.dart';
import 'deliveries_tab.dart';
import 'home_parts.dart';
import 'profile_screen.dart';

/// Главный экран экспедитора: разделы «Доставки» (рейс по точкам, см. [DeliveriesTab]), «Касса» и «Профиль».
/// Сразу показывает то, что на телефоне, и обновляет с сервера; нет связи — работает с тем, что есть; выдачи и
/// оплаты ушли на сервер — данные обновляются (долги магазинов).
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

  /// Открытый раздел: «Перейти к сдаче кассы» переключает на «Кассу».
  int _tab = 0;
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
      index: _tab,
      onIndex: (i) => setState(() => _tab = i),
      tabs: const [
        TabItem('Доставки', Icons.local_shipping_outlined, Icons.local_shipping),
        TabItem('Касса', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
        TabItem('Профиль', Icons.person_outline, Icons.person),
      ],
      pages: [
        DeliveriesTab(
          data: data,
          loading: _loading,
          syncError: _syncError,
          onRefresh: _pull,
          deliveries: widget.deliveries,
          workday: widget.workday,
          expeditor: widget.session.name,
          onCash: () => setState(() => _tab = 1),
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
}
