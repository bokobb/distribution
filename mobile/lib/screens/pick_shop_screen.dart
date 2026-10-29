import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../format.dart';
import '../geo.dart';
import '../location.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/layout.dart';
import '../workday.dart';
import 'agent_map_screen.dart';
import 'agent_order_screen.dart';
import 'new_outlet_screen.dart';
import 'no_order_screen.dart';

/// «Создать заказ» по макету AgentPickShop: магазин — по GPS из всей базы компании. Вверху — у какого магазина вы
/// сейчас (в радиусе визита): «Заказ здесь» или «Без заказа». Ниже — магазины рядом (до 600 м); поиск по названию
/// и адресу — по всей базе. У своих магазинов видны долг и просрочка, у чужих — только адрес. «Новый магазин» —
/// если его нет в базе. Выбрали магазин — начинается визит (далеко — с вопросом) и открывается заказ; заказ
/// отправлен или визит закончен без заказа — экран закрывается.
class PickShopScreen extends StatefulWidget {
  const PickShopScreen({super.key, required this.data, required this.visits, required this.workday});

  final AgentData data;
  final VisitBook visits;
  final Workday workday;

  @override
  State<PickShopScreen> createState() => _PickShopScreenState();
}

class _PickShopScreenState extends State<PickShopScreen> {
  /// «Рядом» — не дальше стольких метров.
  static const nearby = 600;

  Fix? _fix;
  bool _locating = true;
  bool _busy = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _fix = widget.workday.lastPlace;
    _locate();
  }

  Future<void> _locate() async {
    final f = await widget.visits.location.current();
    if (!mounted) return;
    setState(() {
      _fix = f ?? _fix;
      _locating = false;
    });
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  int? _meters(Outlet o) {
    final f = _fix;
    if (f == null || o.lat == null || o.lng == null) return null;
    return metersBetween(f.lat, f.lng, o.lat!, o.lng!);
  }

  /// Вы у магазина: ближайший в радиусе визита (с поправкой на точность GPS).
  (Outlet, int)? _here(List<(Outlet, int)> byDistance) {
    if (byDistance.isEmpty) return null;
    final (o, m) = byDistance.first;
    final allowance = (_fix?.accuracy ?? 0).clamp(0, VisitBook.accuracyAllowance);
    return m - allowance <= widget.data.settings.visitRadius ? (o, m) : null;
  }

  /// Начать визит (или продолжить идущий здесь) и открыть заказ или «Без заказа».
  Future<void> _open(Outlet o, {bool noOrder = false}) async {
    if (!widget.workday.open) return _say('Сначала начните рабочий день на главном экране');
    final current = widget.visits.current;
    if (current != null && current.outletId != o.id) {
      final name = widget.data.outlet(current.outletId)?.name ?? 'другой магазин';
      return _say('Идёт визит: $name — сначала закончите его');
    }
    if (current == null) {
      setState(() => _busy = true);
      try {
        final radius = widget.data.settings.visitRadius;
        final problem = await widget.visits.start(o,
            routeId: widget.data.routeOf(o.id)?.id, radius: radius, confirmFar: (d) => _confirmFar(d, radius));
        if (!mounted) return;
        if (problem != null) return _say(problem);
        if (widget.visits.current == null) return; // передумал начинать издалека
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => noOrder
            ? NoOrderScreen(outlet: o, data: widget.data, visits: widget.visits)
            : AgentOrderScreen(outlet: o, data: widget.data, visits: widget.visits),
      ),
    );
    if (done == true && mounted) Navigator.pop(context, true);
  }

  Future<bool> _confirmFar(int distance, int radius) async =>
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

  Future<void> _newOutlet() async {
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => NewOutletScreen(
                data: widget.data, visits: widget.visits, routeId: widget.data.routes.firstOrNull?.id)));
    if (saved == true && mounted) {
      _say('Магазин сохранён. После отправки он появится в базе «на проверке»');
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.data.base.where((o) => o.status != 'CLOSED').toList();
    // на одном расстоянии — как в базе: свои раньше чужих
    final order = {for (final (i, o) in base.indexed) o.id: i};
    final byDistance = [
      for (final o in base)
        if (_meters(o) case final m?) (o, m),
    ]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : order[a.$1.id]!.compareTo(order[b.$1.id]!));
    final q = _query.trim().toLowerCase();
    final here = q.isEmpty ? _here(byDistance) : null;

    final String title, note;
    final List<Outlet> rows;
    if (q.isNotEmpty) {
      final found = base.where((o) => [o.name, o.address, o.landmark, o.owner].nonNulls.join(' ').toLowerCase().contains(q));
      final far = <Outlet>[];
      final near = <(Outlet, int)>[];
      for (final o in found) {
        final m = _meters(o);
        if (m == null) {
          far.add(o);
        } else {
          near.add((o, m));
        }
      }
      near.sort((a, b) => a.$2.compareTo(b.$2));
      rows = [for (final (o, _) in near) o, ...far];
      title = 'Найдено в базе';
      note = plural(rows.length, 'магазин', 'магазина', 'магазинов');
    } else if (_fix == null) {
      rows = [...widget.data.outlets.values]..sort((a, b) => a.name.compareTo(b.name));
      title = 'Ваши магазины';
      note = _locating ? 'определяю, где вы…' : 'GPS не ответил — найдите поиском';
    } else {
      rows = [
        for (final (o, m) in byDistance)
          if (m <= nearby && o.id != here?.$1.id) o,
      ];
      title = 'Рядом';
      note = 'до $nearby м · в базе ${plural(base.length, 'магазин', 'магазина', 'магазинов')}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Создать заказ'),
            Text('Выберите магазин', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text2)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AgentMapScreen(data: widget.data, visits: widget.visits, workday: widget.workday))),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.text,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.fromLTRB(11, 0, 14, 0),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('На карте'),
            ),
          ),
        ],
        bottom: _busy
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Название или адрес — вся база',
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          if (here != null) ...[_hereCard(here.$1, here.$2), const SizedBox(height: 18)],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(note,
                      textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration:
                  const BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(16))),
              child: Text(
                  q.isNotEmpty
                      ? 'В базе такого магазина нет — создайте его ниже'
                      : 'Рядом магазинов нет — найдите магазин поиском',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.text2)),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final (i, o) in rows.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 0),
                  _row(o, here: o.id == here?.$1.id),
                ],
              ]),
            ),
          const SizedBox(height: 12),
          _newOutletTile(),
        ],
      ),
    );
  }

  Widget _hereCard(Outlet o, int meters) {
    final last = widget.data.lastOrders[o.id];
    final accuracy = _fix?.accuracy;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: AppColors.accent, spreadRadius: 1.5),
          BoxShadow(color: Color(0x804136F1), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
                width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Вы сейчас у этого магазина',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentPressed)),
            ),
            Text([distanceLabel(meters), if (accuracy != null) 'GPS $accuracy м'].join(' · '),
                style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
          ]),
          const SizedBox(height: 10),
          Text(o.name, style: Theme.of(context).textTheme.titleLarge!.copyWith(fontSize: 20, height: 26 / 20)),
          if ([o.legal, o.owner, o.address ?? o.landmark].nonNulls.isNotEmpty)
            Text([o.legal, o.owner, o.address ?? o.landmark].nonNulls.join(' · '),
                style: const TextStyle(fontSize: 14, color: AppColors.text2)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (o.mine && o.debt > 0) Tag('Долг ${money(o.debt)}'),
            if (o.mine && o.overdue > 0) Tag.warn('Просрочено ${money(o.overdue)}'),
            if (o.pending) const Tag('На проверке'),
            if (last != null) Tag('Прошлый заказ ${last.date.day} ${monthsOf[last.date.month - 1].substring(0, 3)}'),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              flex: 16,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _open(o),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward, size: 20),
                label: const Text('Заказ здесь'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 10,
              child: TextButton(
                onPressed: _busy ? null : () => _open(o, noOrder: true),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.fill,
                  foregroundColor: AppColors.text,
                  minimumSize: const Size.fromHeight(50),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                  textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
                ),
                child: const Text('Без заказа'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// Метка справа: вы здесь, просрочка, долг (только у своих), на проверке.
  Widget? _chip(Outlet o, {required bool here}) {
    if (here) {
      return const Tag('Вы здесь', color: AppColors.accentPressed, background: AppColors.accentSoft);
    }
    if (o.mine && o.overdue > 0) return const Tag.warn('Просрочка');
    if (o.mine && o.debt > 0) return Tag('Долг ${money(o.debt)}');
    if (o.pending) return const Tag('На проверке', color: AppColors.accentPressed, background: AppColors.accentSoft);
    return null;
  }

  Widget _row(Outlet o, {required bool here}) {
    final m = _meters(o);
    final chip = _chip(o, here: here);
    final place = [o.address ?? o.landmark, o.owner].nonNulls.join(' · ');
    return InkWell(
      onTap: _busy ? null : () => _open(o),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (place.isNotEmpty)
                    Text(place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (m != null)
                  Text(distanceLabel(m),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2, fontFeatures: tabular)),
                if (chip != null) ...[const SizedBox(height: 4), chip],
              ],
            ),
            const Icon(Icons.chevron_right, color: AppColors.icon),
          ]),
        ),
      ),
    );
  }

  Widget _newOutletTile() => Material(
        color: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: Color(0xFFC9CDD5), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _newOutlet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                    const BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.all(Radius.circular(12))),
                child: const Icon(Icons.add_business_outlined, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Новый магазин', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('Магазина нет в базе — создать с нуля', style: TextStyle(fontSize: 13, color: AppColors.text2)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.icon),
            ]),
          ),
        ),
      );
}
