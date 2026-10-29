import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../data/new_outlet.dart';
import '../data/order.dart';
import '../data/visit.dart';
import '../format.dart';
import '../geo.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/layout.dart';
import '../widgets/workday_card.dart';
import '../workday.dart';
import 'agent_order_screen.dart';
import 'home_parts.dart';
import 'my_path_screen.dart';
import 'order_actions.dart';
import 'pick_shop_screen.dart';

/// «Сегодня» торгового по макету AgentToday: «Создать заказ» (магазин по GPS из всей базы; идёт визит —
/// продолжить его), итоги дня — сумма заказов, визиты, возвраты, без заказа; визиты за сегодня с итогом и временем.
/// Рабочий день не начат — сначала «Начать рабочий день».
class AgentTodayTab extends StatelessWidget {
  const AgentTodayTab(
      {super.key,
      required this.data,
      required this.loading,
      this.syncError,
      required this.onRefresh,
      required this.name,
      required this.workday,
      required this.visits,
      required this.newOutlets});

  final AgentData? data;
  final bool loading;
  final String? syncError;
  final Future<void> Function() onRefresh;

  /// Кто вошёл — в подписи шапки.
  final String name;
  final Workday workday;
  final VisitBook visits;

  /// Новые магазины на телефоне, которые ещё не на сервере (или сервер не принял).
  final List<NewOutlet> newOutlets;

  Future<void> _create(BuildContext context, AgentData data) async {
    final current = visits.current;
    final outlet = current == null ? null : data.outlet(current.outletId);
    if (outlet != null) {
      await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => AgentOrderScreen(outlet: outlet, data: data, visits: visits)));
      return;
    }
    if (!workday.open) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала начните рабочий день')));
      return;
    }
    await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => PickShopScreen(data: data, visits: visits, workday: workday)));
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListenableBuilder(
          listenable: Listenable.merge([visits, workday]),
          builder: (context, _) {
            final d = data;
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                PageHeader(
                  title: 'Сегодня',
                  subtitle: '${dayTitle(DateTime.now())} · $name',
                  trailing: [
                    _TrackChip(
                      workday: workday,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => MyPathScreen(data: d, visits: visits, workday: workday))),
                    ),
                  ],
                ),
                _status(),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: WorkdayCard(workday: workday)),
                if (d == null && !loading)
                  const EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Нет данных',
                    text: 'Подключитесь к интернету и потяните экран вниз, чтобы получить магазины и товары.',
                  ),
                if (d != null) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: _createCard(context, d)),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 0), child: _totals()),
                  if (newOutlets.isNotEmpty) ..._pendingOutlets(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                    child: Text('Визиты сегодня', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _visits(context, d)),
                ],
                if (workday.open && workday.startedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Рабочий день начат в ${time(workday.startedAt!)}',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                  ),
              ],
            );
          },
        ),
      );

  Widget _status() {
    final String text;
    final err = syncError;
    if (loading && data == null) {
      text = 'Обновляю…';
    } else if (err != null) {
      text = data == null ? err : '$err. Данные ${when(data!.syncedAt)}';
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(err != null ? Icons.cloud_off_outlined : Icons.sync, size: 16, color: err != null ? AppColors.err : AppColors.text2),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: err != null ? AppColors.err : AppColors.text2)),
          ),
        ],
      ),
    );
  }

  /// Ближайший магазин в радиусе визита — по последней точке рабочего дня.
  (Outlet, int)? _near(AgentData data) {
    final f = workday.lastPlace;
    if (f == null) return null;
    (Outlet, int)? best;
    for (final o in data.base) {
      if (o.lat == null || o.lng == null) continue;
      final m = metersBetween(f.lat, f.lng, o.lat!, o.lng!);
      if (best == null || m < best.$2) best = (o, m);
    }
    final allowance = (f.accuracy ?? 0).clamp(0, VisitBook.accuracyAllowance);
    return best != null && best.$2 - allowance <= data.settings.visitRadius ? best : null;
  }

  Widget _createCard(BuildContext context, AgentData data) {
    final current = visits.current;
    final String hint;
    if (current != null) {
      hint = 'Идёт визит: ${data.outlet(current.outletId)?.name ?? 'магазин'} — продолжить';
    } else if (_near(data) case (final o, final m)) {
      hint = 'Вы здесь: ${o.name} · ${distanceLabel(m)}';
    } else {
      hint = 'Магазин — по GPS или поиском';
    }
    return Material(
      color: AppColors.accent,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      elevation: 0,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        onTap: () => _create(context, data),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            boxShadow: [BoxShadow(color: Color(0xB34136F1), blurRadius: 28, offset: Offset(0, 14), spreadRadius: -14)],
          ),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: Color(0x2EFFFFFF), shape: BoxShape.circle),
              child: Icon(current != null ? Icons.shopping_cart_outlined : Icons.add, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(current != null ? 'Продолжить заказ' : 'Создать заказ',
                      style: const TextStyle(fontSize: 19, height: 24 / 19, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.place_outlined, size: 16, color: Color(0xE0FFFFFF)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, height: 20 / 14, color: Color(0xE0FFFFFF))),
                    ),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }

  /// Итоги дня: заказы (без отменённых), визиты, возвраты с заказами, без заказа.
  Widget _totals() {
    final orders = [
      for (final o in visits.todayOrders)
        if (o.error == null && o.status != 'CANCELLED' && o.status != 'REFUSED') o
    ];
    final sum = orders.fold(0, (a, o) => a + o.total);
    final back = orders.fold(0, (a, o) => a + o.returnTotal);
    final today = visits.today;
    final noOrder = today.where((v) => v.result == 'NO_ORDER').length;
    Widget cell(String label, String value, {bool first = false}) => Expanded(
          child: Container(
            padding: EdgeInsets.only(left: first ? 0 : 12),
            decoration: first ? null : const BoxDecoration(border: Border(left: BorderSide(color: AppColors.divider))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                Text(value,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular)),
              ],
            ),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Заказы за сегодня', style: TextStyle(fontSize: 13, color: AppColors.text2)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(money(sum),
                        style: const TextStyle(
                            fontSize: 26, height: 32 / 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, fontFeatures: tabular)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(plural(orders.length, 'заказ', 'заказа', 'заказов'),
                    style: const TextStyle(fontSize: 14, color: AppColors.text2)),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 10),
            Row(children: [
              cell('Визиты', '${today.length}', first: true),
              cell('Возвраты', money(back)),
              cell('Без заказа', '$noOrder'),
            ]),
          ],
        ),
      ),
    );
  }

  List<Widget> _pendingOutlets() => [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Text('Новые магазины', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, o) in newOutlets.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 0),
                ListTile(
                  leading: Icon(o.error != null ? Icons.error_outline : Icons.cloud_upload_outlined,
                      color: o.error != null ? AppColors.err : AppColors.text2),
                  title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      o.error != null ? 'Сервер не принял: ${o.error}' : 'Ждёт отправки · ${o.address ?? o.landmark ?? o.phone}',
                      style: TextStyle(color: o.error != null ? AppColors.err : AppColors.text2)),
                ),
              ],
            ]),
          ),
        ),
      ];

  Widget _visits(BuildContext context, AgentData data) {
    final list = visits.today.reversed.toList();
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: const BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(16))),
        child: const Text('Визитов пока нет — у магазина нажмите «Создать заказ»',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.text2)),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (final (i, v) in list.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 0, endIndent: 0),
            if (visits.orderOf(v) case final order)
              _VisitRow(
                visit: v,
                outlet: data.outlet(v.outletId),
                order: order,
                onTap: v.open
                    ? () => _create(context, data)
                    : order == null
                        ? null
                        : () => showOrderActions(context,
                            order: order, data: data, visits: visits, onChanged: onRefresh),
              ),
          ],
        ]),
      ),
    );
  }
}

String _lower(String s) => s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';

/// Визит за сегодня: кружок с итогом, магазин, что вышло, время. С заказом — нажать: изменить или отменить.
class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.visit, required this.outlet, required this.order, this.onTap});

  final Visit visit;
  final Outlet? outlet;
  final Order? order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v = visit, o = order;
    final (Color bg, IconData icon, Color fg) = switch (v) {
      _ when v.error != null || o?.error != null => (AppColors.errBg, Icons.error_outline, AppColors.err),
      _ when v.open => (AppColors.warnBg, Icons.more_horiz, AppColors.warn),
      _ when o?.status == 'CANCELLED' || o?.status == 'REFUSED' => (AppColors.fill, Icons.close, AppColors.text2),
      _ when v.result == 'ORDER' => (AppColors.okBg, Icons.check, AppColors.ok),
      _ => (AppColors.fill, Icons.remove, AppColors.text2),
    };
    final isNew = outlet?.pending == true;
    final String line;
    if (v.error != null) {
      line = 'Сервер не принял: ${v.error}';
    } else if (v.open) {
      line = 'Визит идёт — нажмите, чтобы продолжить';
    } else if (v.result == 'ORDER' && o != null) {
      line = [
        isNew ? 'заказ ${money(o.total)}' : 'Заказ ${money(o.total)}',
        if (o.returnTotal > 0) 'возврат ${money(o.returnTotal)}',
        if (o.error != null)
          'сервер не принял: ${o.error}'
        else if (!o.sent)
          'ждёт отправки'
        else if (o.status == 'NEEDS_APPROVAL')
          'ждёт руководителя'
        else if (o.status == 'CANCELLED' || o.status == 'REFUSED')
          _lower(o.note ?? o.statusLabel ?? 'отменён'),
      ].join(' · ');
    } else if (v.result == 'ORDER') {
      line = isNew ? 'заказ' : 'Заказ';
    } else {
      final why = v.reason;
      line = why == null || why.isEmpty ? 'Без заказа' : 'Без заказа · ${why[0].toLowerCase()}${why.substring(1)}';
    }
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 16, 9),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: isNew && v.result == 'ORDER' ? AppColors.accentSoft : bg, shape: BoxShape.circle),
              child: Icon(isNew && v.result == 'ORDER' ? Icons.add_business_outlined : icon,
                  size: 16, color: isNew && v.result == 'ORDER' ? AppColors.accent : fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(outlet?.name ?? 'Магазин ${v.outletId}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text.rich(
                    TextSpan(children: [
                      if (isNew && v.result == 'ORDER')
                        const TextSpan(
                            text: 'Новый магазин · ',
                            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.accentPressed)),
                      TextSpan(text: line),
                    ]),
                    style: TextStyle(
                        fontSize: 13,
                        color: v.error != null || o?.error != null ? AppColors.err : AppColors.text2,
                        fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(time(v.startedAt), style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
            if (o != null && !v.open) ...[
              const SizedBox(width: 2),
              const Icon(Icons.more_vert, size: 18, color: AppColors.icon, semanticLabel: 'Изменить или отменить'),
            ],
          ]),
        ),
      ),
    );
  }
}

/// «Путь пишется» в шапке «Сегодня», пока идёт рабочий день; нажать — «Мой путь».
class _TrackChip extends StatelessWidget {
  const _TrackChip({required this.workday, required this.onTap});

  final Workday workday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => !workday.open
      ? const SizedBox.shrink()
      : Material(
          color: AppColors.okBg,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 36,
              padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: workday.gpsOff ? AppColors.err : AppColors.ok, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(workday.gpsOff ? 'GPS выключен' : 'Путь пишется',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0B5A40))),
                ],
              ),
            ),
          ),
        );
}
