import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../data/order.dart';
import '../format.dart';
import '../theme.dart';
import '../visits.dart';
import 'agent_order_screen.dart';

enum _Act { edit, cancel, outlet }

/// Заказ из «Визитов сегодня» или «Заказов» — что с ним можно сделать. Пока его не отгрузили экспедитору —
/// «Изменить заказ и возврат» и «Отменить заказ» с причиной (отправленный остаётся в истории «Отменён»,
/// неотправленный стирается с телефона); отгружен или закрыт — почему нельзя. [onOutlet] — ещё «Карточка
/// магазина». Изменили или отменили — [onChanged] (обновить данные с сервера).
Future<void> showOrderActions(BuildContext context,
    {required Order order,
    required AgentData data,
    required VisitBook visits,
    VoidCallback? onOutlet,
    Future<void> Function()? onChanged}) async {
  final outlet = data.outlet(order.outletId);
  final can = order.editable && outlet != null;
  final act = await showModalBottomSheet<_Act>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.card,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(outlet?.name ?? 'Магазин', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
                [
                  order.number ?? 'не отправлен',
                  plural(order.items.length, 'позиция', 'позиции', 'позиций'),
                  money(order.total),
                  if (order.returnTotal > 0) 'возврат ${money(order.returnTotal)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 14, color: AppColors.text2, fontFeatures: tabular)),
          ]),
        ),
        if (can) ...[
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: AppColors.text),
            title: const Text('Изменить заказ и возврат', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(c, _Act.edit),
          ),
          ListTile(
            leading: const Icon(Icons.cancel_outlined, color: AppColors.err),
            title: const Text('Отменить заказ', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.err)),
            subtitle: Text(order.sent
                ? 'Останется в истории как «Отменён»'
                : 'Ещё не отправлен — сотрётся с телефона'),
            onTap: () => Navigator.pop(c, _Act.cancel),
          ),
        ] else
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.all(Radius.circular(12))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lock_outline, size: 18, color: AppColors.text2),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(_locked(order, outlet),
                      style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.label))),
            ]),
          ),
        if (onOutlet != null && outlet != null)
          ListTile(
            leading: const Icon(Icons.storefront_outlined, color: AppColors.text),
            title: const Text('Карточка магазина'),
            onTap: () => Navigator.pop(c, _Act.outlet),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (act == null || !context.mounted) return;
  void say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  switch (act) {
    case _Act.outlet:
      onOutlet!();
    case _Act.edit:
      final saved = await Navigator.push<bool>(context,
          MaterialPageRoute(builder: (_) => AgentOrderScreen(outlet: outlet!, data: data, visits: visits, editing: order)));
      if (saved != true || !context.mounted) return;
      say('Заказ изменён');
      await onChanged?.call();
    case _Act.cancel:
      final reason = await showDialog<String>(context: context, builder: (_) => CancelOrderDialog(sent: order.sent));
      if (reason == null || !context.mounted) return;
      final problem = await visits.cancelOrder(order, reason);
      if (!context.mounted) return;
      say(problem ?? 'Заказ отменён');
      if (problem == null) await onChanged?.call();
  }
}

/// Почему заказ уже не изменить.
String _locked(Order o, Outlet? outlet) => switch (o) {
      _ when outlet == null => 'Магазина нет в данных на телефоне — обновите данные',
      _ when o.error != null => 'Сервер не принял заказ: ${o.error}',
      _ when o.status == 'CANCELLED' => o.note ?? 'Заказ отменён',
      _ when o.status == 'REFUSED' => o.note ?? 'Магазин отказался от заказа при доставке',
      _ when o.status == 'DELIVERED' || o.status == 'PARTIAL' => 'Заказ уже доставлен',
      _ => 'Заказ уже «${o.statusLabel ?? o.status}» — изменить или отменить его может только оператор',
    };

/// Почему отменяют заказ: частые причины одним касанием или своими словами.
class CancelOrderDialog extends StatefulWidget {
  const CancelOrderDialog({super.key, required this.sent});

  /// Заказ уже на сервере — останется в истории; нет — сотрётся с телефона.
  final bool sent;

  static const reasons = ['Клиент передумал', 'Ошибка в заказе', 'Заказ повторно'];

  @override
  State<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<CancelOrderDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  widget.sent
                      ? 'Заказ не поедет к магазину и останется в истории как «Отменён».'
                      : 'Заказ ещё не отправлен — он сотрётся с телефона.',
                  style: const TextStyle(fontSize: 14, color: AppColors.label)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final r in CancelOrderDialog.reasons)
                    ActionChip(label: Text(r), onPressed: () => setState(() => _c.text = r)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _c,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Причина'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Назад')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.err),
            onPressed: _c.text.trim().isEmpty ? null : () => Navigator.pop(context, _c.text.trim()),
            child: const Text('Отменить заказ'),
          ),
        ],
      );
}
