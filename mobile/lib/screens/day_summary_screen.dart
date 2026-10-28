import 'package:flutter/material.dart';

import '../data/expeditor_data.dart';
import '../day_summary.dart';
import '../deliveries.dart';
import '../format.dart';
import '../theme.dart';

/// «Итог дня» экспедитора — что сдавать вечером по каждому рейсу в работе: наличные в кассу, Kaspi на сверку, что
/// ушло в долг магазинам, возвраты негодного и невыданный товар. Обновляется сам: выдачи на телефоне и свежие данные
/// с сервера. Что-то не отправлено — подсказка отправить до сдачи кассы.
class DaySummaryScreen extends StatelessWidget {
  const DaySummaryScreen({super.key, required this.data, required this.deliveries});

  final ValueNotifier<ExpeditorData?> data;
  final DeliveryBook deliveries;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Итог дня')),
        body: ListenableBuilder(
          listenable: Listenable.merge([data, deliveries, deliveries.outbox]),
          builder: (context, _) {
            final d = data.value;
            final trips = d?.current ?? const <TripInfo>[];
            if (d == null || trips.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Рейса в работе нет', style: TextStyle(color: AppColors.inkSoft)),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final t in trips)
                  _TripCard(summary: TripSummary.of(t, deliveries, d.syncedAt), today: d.date, deliveries: deliveries),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Данные сервера ${when(d.syncedAt)}; что ещё на телефоне — уже учтено.',
                      style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                ),
              ],
            );
          },
        ),
      );
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.summary, required this.today, required this.deliveries});

  final TripSummary summary;
  final DateTime today;
  final DeliveryBook deliveries;

  @override
  Widget build(BuildContext context) {
    final s = summary, t = summary.trip;
    final outbox = deliveries.outbox;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                [
                  t.date.isBefore(today) ? 'С ${date(t.date)}' : 'Сегодня',
                  t.number,
                  if (t.vehicle != null) t.vehicle!,
                ].join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
            const SizedBox(height: 4),
            Text('Пройдено ${s.done} из ${t.stops.length}', style: const TextStyle(fontSize: 16)),
            Text(
                [
                  if (s.full > 0) 'выдано ${s.full}',
                  if (s.partial > 0) 'частично ${s.partial}',
                  if (s.refused > 0) 'отказ ${s.refused}',
                  if (s.left > 0) 'не пройдено ${s.left}',
                ].join(' · '),
                style: const TextStyle(color: AppColors.inkSoft)),
            const Divider(height: 24),
            const Text('Сдать в кассу наличными', style: TextStyle(color: AppColors.inkSoft)),
            Text(money(s.cash), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _Row('Kaspi — сверит оператор', money(s.kaspi)),
            if (s.oldDebt > 0) _Row('из них в счёт долгов', money(s.oldDebt)),
            _Row('Выдано товара на', money(s.deliveredTotal)),
            _Row('Ушло в долг магазинам', money(s.debt)),
            const Divider(height: 24),
            _Row('Возвраты негодного — на склад негодного',
                s.returnsQty == 0 ? 'нет' : '${s.returnsQty} шт · ${money(s.returnsTotal)}'),
            _Row('Невыданный товар — на склад', s.backQty == 0 ? 'нет' : '${s.backQty} шт'),
            if (s.unsent > 0) ...[
              const SizedBox(height: 12),
              Text(
                  'Не отправлено на сервер: ${plural(s.unsent, 'запись', 'записи', 'записей')} — отправьте до сдачи '
                  'кассы',
                  style: const TextStyle(color: AppColors.crimson)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: outbox.sending ? null : outbox.flush,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(outbox.sending ? 'Отправляю…' : 'Отправить сейчас'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
