import 'package:flutter/material.dart';

import '../data/expeditor_data.dart';
import '../day_summary.dart';
import '../deliveries.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/layout.dart';
import '../widgets/message_box.dart';
import 'cash_count_screen.dart';

/// «Касса» экспедитора по макету ExpCash — что сдавать вечером по рейсам в работе: наличные на руках (и сколько
/// ожидается, если все заплатят), Kaspi, что ушло в долг магазинам, возвраты негодного; «Получено по заказам» —
/// кто сколько отдал; невыданный товар — вернуть на склад. Обновляется сама: выдачи на телефоне и свежие данные с
/// сервера. Что-то не отправлено — подсказка отправить до сдачи кассы. «Сдать кассу оператору» — пересчёт купюр.
class DaySummaryView extends StatelessWidget {
  const DaySummaryView({super.key, required this.data, required this.deliveries});

  final ValueNotifier<ExpeditorData?> data;
  final DeliveryBook deliveries;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([data, deliveries, deliveries.outbox]),
        builder: (context, _) {
          final d = data.value;
          final trips = d?.current ?? const <TripInfo>[];
          final all = [for (final t in trips) TripSummary.of(t, deliveries, d!.syncedAt)];
          final done = all.fold(0, (a, s) => a + s.done);
          final stops = trips.fold(0, (a, t) => a + t.stops.length);
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              PageHeader(
                  title: 'Касса',
                  subtitle: [dayTitle(DateTime.now()), if (stops > 0) 'доставлено $done из $stops'].join(' · ')),
              if (d == null || trips.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Рейса в работе нет', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2)),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _Body(data: d, trips: trips, summaries: all, deliveries: deliveries),
                ),
            ],
          );
        },
      );
}

/// Строка «Получено по заказам».
typedef _Received = ({String name, DateTime? at, String note, bool kaspi, int amount});

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.trips, required this.summaries, required this.deliveries});

  final ExpeditorData data;
  final List<TripInfo> trips;
  final List<TripSummary> summaries;
  final DeliveryBook deliveries;

  int _sum(int Function(TripSummary s) f) => summaries.fold(0, (a, s) => a + f(s));

  /// Ещё ждём наличными: непройденные точки, где платят наличными.
  int get _pendingCash => [
        for (final t in trips)
          for (final s in t.stops)
            if (!deliveries.done(s.order) && s.order.payment == 'CASH') s.order.total - s.order.paid
      ].fold(0, (a, b) => a + b);

  /// Кто сколько отдал: за заказы и в счёт долга — новые сверху.
  List<_Received> get _received {
    final rows = <_Received>[];
    for (final t in trips) {
      for (final s in t.stops) {
        final local = deliveries.of(s.order.id);
        if (local != null && local.error == null && !local.refused && local.paid > 0) {
          rows.add((
            name: s.outlet.name,
            at: local.deliveredAt,
            note: [local.kaspi > 0 ? 'Kaspi' : 'наличные', if (local.partial) 'частично'].join(' · '),
            kaspi: local.kaspi > 0,
            amount: local.paid,
          ));
        } else if ((local == null || local.error != null) && s.order.done && s.order.paid > 0) {
          rows.add((
            name: s.outlet.name,
            at: null,
            note: [s.order.paymentLabel.toLowerCase(), if (s.order.status == 'PARTIAL') 'частично'].join(' · '),
            kaspi: s.order.payment == 'KASPI',
            amount: s.order.paid,
          ));
        }
      }
      for (final p in deliveries.paymentsIn(t.id)) {
        final name = t.stops.where((s) => s.outlet.id == p.outletId).firstOrNull?.outlet.name ?? 'Магазин';
        rows.add((
          name: name,
          at: p.paidAt,
          note: 'в счёт долга · ${p.method == 'KASPI' ? 'Kaspi' : 'наличные'}',
          kaspi: p.method == 'KASPI',
          amount: p.amount,
        ));
      }
    }
    rows.sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final cash = _sum((s) => s.cash), kaspi = _sum((s) => s.kaspi), oldDebt = _sum((s) => s.oldDebt);
    final debt = _sum((s) => s.debt), back = _sum((s) => s.backQty), unsent = _sum((s) => s.unsent);
    final returnsQty = _sum((s) => s.returnsQty), returnsTotal = _sum((s) => s.returnsTotal);
    final expected = cash + _pendingCash;
    final received = _received;
    final outbox = deliveries.outbox;
    const small = TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(20)), boxShadow: cardShadow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Наличные на руках', style: small),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(cash),
                    style: const TextStyle(
                        fontSize: 34, height: 40 / 34, fontWeight: FontWeight.w700, letterSpacing: -0.6, fontFeatures: tabular)),
              ),
              if (oldDebt > 0) Text('из них в счёт долгов ${money(oldDebt)}', style: small),
              if (expected > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                  child: LinearProgressIndicator(
                      value: (cash / expected).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: AppColors.line,
                      color: AppColors.accent),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: Text('${(cash * 100 / expected).round()}% собрано', style: small)),
                  Text('ожидается ${money(expected)}', style: small),
                ]),
              ],
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _Cell('Kaspi', money(kaspi))),
                    const VerticalDivider(width: 12),
                    Expanded(child: _Cell('В долг', money(debt))),
                    const VerticalDivider(width: 12),
                    Expanded(
                        child: _Cell('Возврат', returnsQty == 0 ? 'нет' : '$returnsQty шт',
                            note: returnsQty == 0 ? null : money(returnsTotal))),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (unsent > 0) ...[
          const SizedBox(height: 12),
          MessageBox.warn(
              'Не отправлено на сервер: ${plural(unsent, 'запись', 'записи', 'записей')} — отправьте до сдачи кассы'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: outbox.sending ? null : outbox.flush,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(outbox.sending ? 'Отправляю…' : 'Отправить сейчас'),
            ),
          ),
        ],
        if (received.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Expanded(
                    child: Text('Получено по заказам', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                Text('${received.length}', style: small),
              ],
            ),
          ),
          GroupCard(children: [
            for (final r in received)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text([if (r.at != null) time(r.at!), r.note].join(' · '), style: small),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(money(r.amount),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                ]),
              ),
          ]),
        ],
        if (back > 0) ...[
          const SizedBox(height: 12),
          GroupCard(children: [InfoRow(label: 'Невыданный товар — на склад', value: '$back шт')]),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.text, minimumSize: const Size.fromHeight(54)),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      CashCountScreen(expected: cash, kaspi: kaspi, payments: received.where((r) => !r.kaspi).length))),
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Сдать кассу оператору'),
        ),
        const SizedBox(height: 8),
        Text('Данные сервера ${when(data.syncedAt)}; что ещё на телефоне — уже учтено.',
            textAlign: TextAlign.center, style: small),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value, {this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular)),
          ),
          if (note != null) Text(note!, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
        ],
      );
}
