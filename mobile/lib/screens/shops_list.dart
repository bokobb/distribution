import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../geo.dart';
import '../location.dart';
import '../theme.dart';
import '../visits.dart';
import '../workday.dart';
import 'outlet_screen.dart';
import 'shop_facts.dart';
import 'visit_start.dart';

/// Список магазинов по макету AgentRoute: вся база, ближние сверху; поиск по названию, адресу и телефону; фильтры
/// «Рядом» (вся база по расстоянию), «С долгом», «Просрочка» (у своих), «Новые». Строка открывает карточку магазина.
/// «Новый» — магазина нет в базе: создать и сразу оформить заказ. [onMap] — «Карта».
class ShopsList extends StatefulWidget {
  const ShopsList({super.key, required this.data, required this.visits, required this.workday, required this.onMap});

  final AgentData data;
  final VisitBook visits;
  final Workday workday;
  final VoidCallback onMap;

  @override
  State<ShopsList> createState() => _ShopsListState();
}

enum _Filter { near, debt, overdue, fresh }

class _ShopsListState extends State<ShopsList> {
  _Filter _filter = _Filter.near;
  String _query = '';
  Fix? _fix;

  @override
  void initState() {
    super.initState();
    _fix = widget.workday.lastPlace;
    _locate();
  }

  Future<void> _locate() async {
    final f = await widget.visits.location.current();
    if (mounted && f != null) setState(() => _fix = f);
  }

  bool _test(Outlet o) => switch (_filter) {
        _Filter.near => true,
        _Filter.debt => o.mine && o.debt > 0,
        _Filter.overdue => o.mine && o.overdue > 0,
        _Filter.fresh => o.pending,
      };

  bool _matches(Outlet o) {
    final q = _query.trim();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return ShopFacts.matches(o, q) ||
        digits.length >= 4 && [o.phone, o.phone2].nonNulls.any((p) => p.replaceAll(RegExp(r'\D'), '').contains(digits));
  }

  @override
  Widget build(BuildContext context) {
    final f = ShopFacts(data: widget.data, visits: widget.visits, fix: _fix);
    final base = widget.data.base.where((o) => o.status != 'CLOSED').toList();
    final rows = f.byDistance(base.where((o) => _test(o) && _matches(o)));
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Магазины', style: text.headlineMedium),
              const SizedBox(height: 2),
              Text('${base.length} в базе · ${_fix == null ? 'по порядку' : 'ближние сверху'}',
                  style: text.bodyMedium!.copyWith(color: AppColors.text2)),
            ]),
          ),
          FilledButton.icon(
            onPressed: () => newOutletWithOrder(context, data: widget.data, visits: widget.visits, workday: widget.workday),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
            ),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Новый'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Название, адрес, телефон',
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: widget.onMap,
            style: TextButton.styleFrom(
              backgroundColor: AppColors.card,
              foregroundColor: AppColors.text,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.fromLTRB(12, 0, 15, 0),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
            ),
            icon: const Icon(Icons.map_outlined, size: 20),
            label: const Text('Карта'),
          ),
        ]),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          children: [
            for (final (filter, label) in [
              (_Filter.near, 'Рядом'),
              (_Filter.debt, 'С долгом'),
              (_Filter.overdue, 'Просрочка'),
              (_Filter.fresh, 'Новые'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _Chip(label: label, on: _filter == filter, onTap: () => setState(() => _filter = filter)),
              ),
          ],
        ),
      ),
      Expanded(
        child: rows.isEmpty
            ? ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [_empty()])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: rows.length,
                itemBuilder: (context, i) => _row(rows[i], f, first: i == 0, last: i == rows.length - 1),
              ),
      ),
    ]);
  }

  Widget _empty() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: const BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(16))),
        child: Column(children: [
          Text(_query.trim().isEmpty ? 'Таких магазинов нет' : 'Такого магазина нет в базе',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.text2)),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => newOutletWithOrder(context, data: widget.data, visits: widget.visits, workday: widget.workday),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.accentSoft,
              foregroundColor: AppColors.accentPressed,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: const Text('Создать новый магазин'),
          ),
        ]),
      );

  /// Строка в общей белой карточке: первая и последняя скругляют её углы.
  Widget _row(Outlet o, ShopFacts f, {required bool first, required bool last}) {
    final m = f.meters(o);
    final chip = f.listChip(o);
    final place = [o.address ?? o.landmark, o.owner].nonNulls.join(' · ');
    final radius = BorderRadius.vertical(
        top: first ? const Radius.circular(16) : Radius.zero, bottom: last ? const Radius.circular(16) : Radius.zero);
    return Material(
      color: AppColors.card,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    OutletScreen(outlet: o, data: widget.data, visits: widget.visits, workday: widget.workday))),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: BoxDecoration(
              border: first ? null : const Border(top: BorderSide(color: AppColors.divider))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (place.isNotEmpty)
                  Text(place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.text2)),
              ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (m != null)
                Text(distanceLabel(m),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2, fontFeatures: tabular)),
              if (chip != null) ...[const SizedBox(height: 4), chip],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: on,
        child: Material(
          color: on ? AppColors.text : AppColors.card,
          shape: StadiumBorder(side: BorderSide(color: on ? AppColors.text : AppColors.field)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.text)),
            ),
          ),
        ),
      );
}
