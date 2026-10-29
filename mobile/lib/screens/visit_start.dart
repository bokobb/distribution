import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../geo.dart';
import '../visits.dart';
import '../workday.dart';
import 'agent_order_screen.dart';
import 'new_outlet_screen.dart';
import 'no_order_screen.dart';

void _say(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// Начать визит в магазине (или продолжить идущий здесь) и открыть заказ или «Без заказа» — откуда бы ни выбрали
/// магазин: «Создать заказ», карта, список, карточка, новый магазин. Рабочий день не начат, идёт визит в другом
/// магазине, GPS не ответил — говорит почему; дальше радиуса — спрашивает. [busy] — пока определяется место.
/// true — заказ отправлен или визит закончен без заказа.
Future<bool> openVisit(BuildContext context,
    {required AgentData data,
    required VisitBook visits,
    required Workday workday,
    required Outlet outlet,
    bool noOrder = false,
    ValueChanged<bool>? busy}) async {
  if (!workday.open) {
    _say(context, 'Сначала начните рабочий день на главном экране');
    return false;
  }
  final current = visits.current;
  if (current != null && current.outletId != outlet.id) {
    _say(context, 'Идёт визит: ${data.outlet(current.outletId)?.name ?? 'другой магазин'} — сначала закончите его');
    return false;
  }
  if (current == null) {
    busy?.call(true);
    try {
      final radius = data.settings.visitRadius;
      final problem = await visits.start(outlet,
          routeId: data.routeOf(outlet.id)?.id, radius: radius, confirmFar: (d) => _confirmFar(context, d, radius));
      if (!context.mounted) return false;
      if (problem != null) {
        _say(context, problem);
        return false;
      }
      if (visits.current == null) return false; // передумал начинать издалека
    } finally {
      busy?.call(false);
    }
  }
  if (!context.mounted) return false;
  final done = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => noOrder
          ? NoOrderScreen(outlet: outlet, data: data, visits: visits)
          : AgentOrderScreen(outlet: outlet, data: data, visits: visits),
    ),
  );
  return done == true;
}

Future<bool> _confirmFar(BuildContext context, int distance, int radius) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Вы в ${distanceLabel(distance)} от магазина'),
        content: Text('Визит отмечается рядом с магазином — не дальше $radius м. Если начать отсюда, директор '
            'увидит визит с пометкой «далеко».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Всё равно начать')),
        ],
      ),
    ) ==
    true;

/// «Новый магазин»: заполнить на месте и сразу оформить в нём заказ (магазин уйдёт на сервер сам, заказ — следом).
/// true — заказ отправлен или визит закончен.
Future<bool> newOutletWithOrder(BuildContext context,
    {required AgentData data, required VisitBook visits, required Workday workday}) async {
  final created = await Navigator.push<Outlet>(
      context,
      MaterialPageRoute(
          builder: (_) => NewOutletScreen(data: data, visits: visits, routeId: data.routes.firstOrNull?.id)));
  if (created == null || !context.mounted) return false;
  if (!workday.open) {
    _say(context, 'Магазин сохранён. Заказ в нём — когда начнёте рабочий день');
    return false;
  }
  return openVisit(context, data: data, visits: visits, workday: workday, outlet: created);
}
