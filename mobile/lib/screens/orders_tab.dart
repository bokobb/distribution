import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../data/order.dart';
import '../format.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/layout.dart';
import '../workday.dart';
import 'order_actions.dart';
import 'outlet_screen.dart';

/// «Заказы» торгового по макету AgentOrders: сегодняшние (с телефона и с сервера) и прошлого рабочего дня — с
/// отметкой «Новый» (ещё не доставлен) или «Доставлен» (экспедитор отдал товар, во сколько). Строка — что можно с
/// заказом: изменить или отменить, пока его не отгрузили, и карточка магазина.
class OrdersTab extends StatefulWidget {
  const OrdersTab(
      {super.key,
      required this.data,
      required this.visits,
      required this.workday,
      required this.onRefresh,
      DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final AgentData data;
  final VisitBook visits;
  final Workday workday;
  final Future<void> Function() onRefresh;
  final DateTime Function() _now;

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  bool _previous = false;

  static const _payments = {'CASH': 'наличные', 'KASPI': 'Kaspi', 'CREDIT': 'в долг'};

  static bool _dropped(Order o) => o.error != null || o.status == 'CANCELLED' || o.status == 'REFUSED';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.visits,
        builder: (context, _) {
          final now = widget._now();
          final today = DateUtils.dateOnly(now);
          final todays = widget.visits.todayOrders.reversed.toList();
          final prevDay = widget.data.previousDate;
          // прошлый день: доставленные по времени выдачи, потом остальные
          final prev = [...widget.data.previousOrders]..sort((a, b) {
              final da = a.deliveredAt, db = b.deliveredAt;
              if (da != null && db != null) return da.compareTo(db);
              if (da != null || db != null) return da != null ? -1 : 1;
              return a.createdAt.compareTo(b.createdAt);
            });
          final prevLabel = prevDay == null || prevDay == today.subtract(const Duration(days: 1)) ? 'Вчера' : dayMon(prevDay);
          final list = _previous ? prev : todays;
          final live = list.where((o) => !_dropped(o)).toList();
          final sum = live.fold(0, (a, o) => a + o.total);
          return RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                PageHeader(title: 'Заказы', subtitle: dayTitle(now)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: PillTabs(
                    labels: ['Сегодня · ${todays.length}', '$prevLabel · ${prev.length}'],
                    index: _previous ? 1 : 0,
                    onChanged: (i) => setState(() => _previous = i == 1),
                  ),
                ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      decoration:
                          const BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(16))),
                      child: Text(
                          _previous
                              ? 'За две недели заказов не было'
                              : 'Заказов сегодня пока нет — у магазина нажмите «Создать заказ» на «Сегодня»',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Expanded(
                        child: Text(_previous ? _deliveredHead(prev, today) : _takenHead(live),
                            style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                      ),
                      const SizedBox(width: 12),
                      Text(money(sum),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(children: [
                          for (final (i, o) in list.indexed) ...[
                            if (i > 0) const Divider(height: 1, indent: 0, endIndent: 0),
                            _row(o, today),
                          ],
                        ]),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Wrap(spacing: 14, runSpacing: 6, children: [
                      _Dot(color: AppColors.accent, label: 'Новый — ещё не доставлен'),
                      _Dot(color: AppColors.ok, label: 'Доставлен — экспедитор отдал товар'),
                    ]),
                  ),
                ],
              ],
            ),
          );
        },
      );

  /// «Взято 5 заказов»: день доставки торговый не выбирает — его ставит склад при отгрузке.
  String _takenHead(List<Order> live) => live.isEmpty ? 'Заказов нет' : 'Взято ${plural(live.length, 'заказ', 'заказа', 'заказов')}';

  /// «Сегодня доставлено 5 из 14»: отменённые не считаются.
  String _deliveredHead(List<Order> prev, DateTime today) {
    final waiting = prev.where((o) => !_dropped(o)).toList();
    final done = waiting.where((o) => o.deliveredAt != null).toList();
    final todayOnly = done.isNotEmpty && done.every((o) => DateUtils.isSameDay(o.deliveredAt, today));
    return '${todayOnly ? 'Сегодня доставлено' : 'Доставлено'} ${done.length} из ${waiting.length}';
  }

  Widget _row(Order o, DateTime today) {
    final outlet = widget.data.outlet(o.outletId);
    final positions = plural(o.items.length, 'позиция', 'позиции', 'позиций');
    final delivered = o.deliveredAt;
    final String meta;
    if (_previous) {
      meta = [
        positions,
        _payments[o.payment] ?? o.payment,
        if (delivered != null) DateUtils.isSameDay(delivered, today) ? 'в ${time(delivered)}' : '${dayMon(delivered)} в ${time(delivered)}',
        if (_dropped(o) && o.note != null) o.note!,
      ].join(' · ');
    } else {
      meta = [
        time(o.createdAt),
        if (outlet?.pending == true) 'новый магазин',
        positions,
        if (o.status == 'NEEDS_APPROVAL') 'сверх лимита',
        if (o.returnTotal > 0) 'возврат ${money(o.returnTotal)}',
        if (o.error != null) 'сервер не принял: ${o.error}' else if (!o.sent) 'ждёт отправки',
        if (o.error == null && _dropped(o) && o.note != null) o.note!,
      ].join(' · ');
    }
    final badge = switch (o) {
      _ when o.error != null => const _Badge.err('Не принят'),
      _ when o.status == 'CANCELLED' => _Badge(o.statusLabel ?? 'Отменён'),
      _ when o.status == 'REFUSED' => _Badge.err(o.statusLabel ?? 'Отказ'),
      _ when delivered != null && o.status == 'PARTIAL' => const _Badge.ok('Частично'),
      _ when delivered != null => const _Badge.ok('Доставлен'),
      _ => const _Badge.brand('Новый'),
    };
    return InkWell(
      onTap: () => showOrderActions(context,
          order: o,
          data: widget.data,
          visits: widget.visits,
          onChanged: widget.onRefresh,
          onOutlet: outlet == null
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          OutletScreen(outlet: outlet, data: widget.data, visits: widget.visits, workday: widget.workday)))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(outlet?.name ?? 'Магазин', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(meta,
                    style: TextStyle(
                        fontSize: 13, color: o.error != null ? AppColors.err : AppColors.text2, fontFeatures: tabular)),
              ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(o.total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular)),
              const SizedBox(height: 3),
              badge,
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Отметка заказа справа: «Новый», «Доставлен», «Отменён».
class _Badge extends StatelessWidget {
  const _Badge(this.text)
      : color = AppColors.label,
        background = AppColors.fill;

  const _Badge.brand(this.text)
      : color = AppColors.accentPressed,
        background = AppColors.accentSoft;

  const _Badge.ok(this.text)
      : color = const Color(0xFF0E6B4C),
        background = AppColors.okBg;

  const _Badge.err(this.text)
      : color = const Color(0xFFA3241A),
        background = AppColors.errBg;

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(color: background, borderRadius: const BorderRadius.all(Radius.circular(5))),
        child: Center(
            widthFactor: 1,
            child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color))),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
      ]);
}
