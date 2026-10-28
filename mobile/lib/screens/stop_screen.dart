import 'package:flutter/material.dart';

import '../data/expeditor_data.dart';
import '../format.dart';
import '../launch.dart';
import '../theme.dart';

/// Точка рейса: что везём (заказ с составом и суммой, как оплачивает), магазин — долг, телефон, адрес;
/// «Позвонить» и «Маршрут» (карты на телефоне).
class StopScreen extends StatelessWidget {
  const StopScreen({super.key, required this.stop, required this.trip, required this.data});

  final Stop stop;
  final TripInfo trip;
  final ExpeditorData data;

  @override
  Widget build(BuildContext context) {
    final o = stop.outlet;
    final order = stop.order;
    final hasPlace = o.lat != null && o.lng != null || o.address != null || o.landmark != null;
    return Scaffold(
      appBar: AppBar(title: Text(o.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              if (o.phone != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => call(context, o.phone!),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Позвонить'),
                  ),
                ),
              if (o.phone != null && hasPlace) const SizedBox(width: 8),
              if (hasPlace)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => route(context, lat: o.lat, lng: o.lng, name: o.name, address: o.address ?? o.landmark),
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Маршрут'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Заказ ${order.number}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text(
                      [
                        order.paymentLabel,
                        'доставка ${date(order.deliveryDate)}',
                        if (order.agent != null) 'принял ${order.agent}',
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.inkSoft)),
                  if (order.done)
                    Text(order.statusLabel, style: TextStyle(color: order.refused ? AppColors.crimson : AppColors.ok)),
                  if (order.comment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Комментарий: ${order.comment}'),
                    ),
                  const Divider(height: 24),
                  for (final l in order.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name),
                                Text(
                                    [
                                      '${l.qty} ${l.unit} × ${money(l.price)}',
                                      if (l.perBox > 1 && l.qty >= l.perBox) _boxes(l),
                                      if (l.delivered != null && l.delivered != l.qty) 'выдано ${l.delivered}',
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                              ],
                            ),
                          ),
                          Text(money(l.sum)),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  Row(children: [
                    const Expanded(child: Text('Итого', style: TextStyle(fontWeight: FontWeight.w600))),
                    Text(money(order.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ]),
                  if (order.paid > 0)
                    Text('Оплачено ${money(order.paid)}', textAlign: TextAlign.end, style: const TextStyle(color: AppColors.ok)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.debt == 0 ? 'Долга нет' : 'Долг ${money(o.debt)}',
                      style: TextStyle(fontSize: 16, color: o.overdue > 0 ? AppColors.crimson : AppColors.ink)),
                  if (o.overdue > 0) Text('просрочено ${money(o.overdue)}', style: const TextStyle(color: AppColors.crimson)),
                  Text('на ${date(data.date)}', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                  const SizedBox(height: 8),
                  if (o.legal != null) Text(o.legal!),
                  if (o.phone != null) Text(o.phone!),
                  if (o.phone2 != null) Text(o.phone2!),
                  if (o.address != null) Text(o.address!),
                  if (o.landmark != null) Text('Ориентир: ${o.landmark}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// «2 кор. + 3 шт».
  static String _boxes(TripLine l) {
    final boxes = l.qty ~/ l.perBox, rest = l.qty % l.perBox;
    return '$boxes кор.${rest > 0 ? ' + $rest ${l.unit}' : ''}';
  }
}
