import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../format.dart';
import '../theme.dart';

/// Карточка магазина: кто, где, прайс, лимит и долг на день синхронизации. Визит и заказ — следующие шаги.
class OutletScreen extends StatelessWidget {
  const OutletScreen({super.key, required this.outlet, required this.data});

  final Outlet outlet;
  final AgentData data;

  @override
  Widget build(BuildContext context) {
    final o = outlet;
    return Scaffold(
      appBar: AppBar(title: Text(o.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (o.pending)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Магазин на проверке у оператора', style: TextStyle(color: AppColors.inkSoft)),
            ),
          _Section(rows: [
            ('Долг', o.debt == 0 ? 'нет' : money(o.debt), o.overLimit),
            if (o.overdue > 0) ('Просрочено', money(o.overdue), true),
            ('Лимит долга', o.creditLimit == 0 ? 'без лимита' : money(o.creditLimit), false),
            ('Отсрочка', plural(o.paymentDays, 'день', 'дня', 'дней'), false),
            if (o.lastPaymentDate != null) ('Последняя оплата', '${money(o.lastPaymentSum)}, ${date(o.lastPaymentDate!)}', false),
            ('Прайс', o.priceLabel, false),
          ]),
          const SizedBox(height: 4),
          Text('На ${date(data.date)}', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          const SizedBox(height: 16),
          _Section(rows: [
            if (o.legal != null) ('Юр. лицо', o.legal!, false),
            if (o.owner != null) ('Владелец', o.owner!, false),
            if (o.phone != null) ('Телефон', o.phone!, false),
            if (o.phone2 != null) ('Телефон 2', o.phone2!, false),
            if (o.address != null) ('Адрес', o.address!, false),
            if (o.landmark != null) ('Ориентир', o.landmark!, false),
            ('Точка на карте', o.lat != null && o.lng != null ? 'есть' : 'нет', false),
          ]),
        ],
      ),
    );
  }
}

/// Строки «подпись — значение»; третье — значение тревожное (малиновым).
class _Section extends StatelessWidget {
  const _Section({required this.rows});

  final List<(String, String, bool)> rows;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              for (final (label, value, alarm) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 140, child: Text(label, style: const TextStyle(color: AppColors.inkSoft))),
                      Expanded(
                        child: SelectableText(value,
                            style: TextStyle(fontWeight: FontWeight.w500, color: alarm ? AppColors.crimson : AppColors.ink)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
