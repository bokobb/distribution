import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/agent_data.dart';
import '../data/agent_repo.dart';
import '../data/new_outlet.dart';
import '../session.dart';
import '../visits.dart';
import '../widgets/layout.dart';
import '../workday.dart';
import 'agent_today_tab.dart';
import 'home_parts.dart';
import 'orders_tab.dart';
import 'profile_screen.dart';
import 'shops_tab.dart';

/// Главный экран торгового: разделы «Сегодня» (создать заказ, итоги и визиты дня), «Заказы» (сегодня и прошлого
/// рабочего дня — доставлены или нет), «Магазины» (карта и список всей базы) и «Профиль». Сразу показывает то, что на телефоне, и обновляет с сервера; нет связи — работает с тем,
/// что есть. Новый магазин с телефона сразу в базе (в нём можно оформить заказ) и в «Новых магазинах», пока не ушёл
/// на сервер; сервер принял — данные обновляются, и он в базе «на проверке» уже с сервера.
class AgentHomeScreen extends StatefulWidget {
  const AgentHomeScreen(
      {super.key,
      required this.repo,
      required this.session,
      required this.workday,
      required this.visits,
      required this.onSession,
      required this.onLogout});

  final AgentRepo repo;
  final Session session;
  final Workday workday;
  final VisitBook visits;
  final ValueChanged<Session> onSession;
  final VoidCallback onLogout;

  @override
  State<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends State<AgentHomeScreen> {
  AgentData? _data;
  bool _loading = true;
  String? _syncError;

  /// Новые магазины на телефоне: все — к данным с сервера; ещё не на сервере (или сервер не принял) — на «Сегодня».
  List<NewOutlet> _local = const [];
  List<NewOutlet> _newOutlets = const [];

  /// Данные с сервера вместе с новыми магазинами с телефона.
  AgentData? _view;
  /// Сколько новых магазинов сервер уже принял, когда экран последний раз брал данные.
  late int _outletsAdded;

  @override
  void initState() {
    super.initState();
    _outletsAdded = widget.visits.outbox.outletsAdded;
    widget.visits.outbox.addListener(_outboxChanged);
    _start();
  }

  @override
  void dispose() {
    widget.visits.outbox.removeListener(_outboxChanged);
    super.dispose();
  }

  /// Отправка прошла: обновить «Новые магазины»; сервер принял магазин — забрать данные, он уже в маршруте.
  Future<void> _outboxChanged() async {
    await _loadNewOutlets();
    final added = widget.visits.outbox.outletsAdded;
    if (added != _outletsAdded && mounted) {
      _outletsAdded = added;
      await _pull();
    }
  }

  Future<void> _loadNewOutlets() async {
    final all = await widget.visits.outbox.store.newOutlets();
    if (!mounted) return;
    setState(() {
      _local = all;
      _newOutlets = [for (final o in all) if (!o.sent || o.error != null) o];
      _view = _data?.withLocal(all);
    });
  }

  Future<void> _start() async {
    final local = await widget.repo.local();
    if (mounted) _show(local);
    await _loadNewOutlets();
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

  /// Данные на экран; интервал GPS и рабочее время — из настроек компании, визиты с сервера — к телефонным.
  void _show(AgentData? data) {
    setState(() {
      _data = data;
      _view = data?.withLocal(_local);
    });
    if (data == null) return;
    widget.workday
      ..setInterval(Duration(minutes: data.settings.gpsInterval))
      ..setHours(data.settings.workStart, data.settings.workEnd);
    widget.visits.serverVisits(data);
  }

  @override
  Widget build(BuildContext context) {
    final data = _view;
    const noData = Center(
        child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Нет данных',
            text: 'Подключитесь к интернету и обновите «Сегодня», чтобы получить магазины.'));
    return HomeShell(
      tabs: const [
        TabItem('Сегодня', Icons.today_outlined, Icons.today),
        TabItem('Заказы', Icons.receipt_long_outlined, Icons.receipt_long),
        TabItem('Магазины', Icons.storefront_outlined, Icons.storefront),
        TabItem('Профиль', Icons.person_outline, Icons.person),
      ],
      pages: [
        AgentTodayTab(
          data: data,
          loading: _loading,
          syncError: _syncError,
          onRefresh: _pull,
          name: widget.session.name,
          workday: widget.workday,
          visits: widget.visits,
          newOutlets: _newOutlets,
        ),
        data == null
            ? noData
            : OrdersTab(data: data, visits: widget.visits, workday: widget.workday, onRefresh: _pull),
        data == null ? noData : ShopsTab(data: data, visits: widget.visits, workday: widget.workday),
        ProfileTab(
          api: widget.repo.api,
          session: widget.session,
          workday: widget.workday,
          dataLabel: 'Каталог и цены',
          syncedAt: data?.syncedAt,
          onRefresh: _pull,
          outletNames: {for (final o in data?.base ?? const <Outlet>[]) o.id: o.name},
          onSession: widget.onSession,
          onLogout: widget.onLogout,
        ),
      ],
    );
  }
}
