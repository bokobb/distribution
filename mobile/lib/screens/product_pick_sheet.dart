import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../data/order.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/layout.dart';

/// Что выбрали в «Добавить товар»: в заказ ([toReturn] = false) или в возврат; [qty] — штук; [reason] — у возврата.
class PickedProduct {
  const PickedProduct({required this.product, required this.toReturn, required this.qty, this.reason});

  final Product product;
  final bool toReturn;
  final int qty;
  final String? reason;
}

/// «Добавить товар» по макету AgentProductPick — лист снизу: «В заказ» / «В возврат», поиск по каталогу, товар
/// с отметкой, сколько его уже в заказе или возврате. Внизу выбранный товар: в заказ — по коробкам (1, 2, 3 кор
/// одним касанием), в возврат — по штукам с причиной; сумма по прайсу магазина.
Future<PickedProduct?> pickProduct(BuildContext context,
        {required AgentData data,
        required Outlet outlet,
        required bool toReturn,
        required Map<int, int> inOrder,
        required Map<int, ReturnItem> inReturn}) =>
    showModalBottomSheet<PickedProduct>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _PickSheet(data: data, outlet: outlet, toReturn: toReturn, inOrder: inOrder, inReturn: inReturn),
      ),
    );

class _PickSheet extends StatefulWidget {
  const _PickSheet(
      {required this.data, required this.outlet, required this.toReturn, required this.inOrder, required this.inReturn});

  final AgentData data;
  final Outlet outlet;
  final bool toReturn;
  final Map<int, int> inOrder;
  final Map<int, ReturnItem> inReturn;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  late bool _return = widget.toReturn;
  String _query = '';
  Product? _selected;
  int _n = 1;
  String _reason = 'EXPIRED';

  int _price(Product p) => p.priceFor(widget.outlet.priceKind);

  /// В заказ — по коробкам, если в коробке больше штуки.
  bool _byBox(Product p) => !_return && p.perBox > 1;

  int _pieces(Product p) => _byBox(p) ? _n * p.perBox : _n;

  String _unit(Product p) => _byBox(p) ? 'кор' : p.unit;

  String _meta(Product p) {
    final price = _price(p);
    if (price == 0) return 'нет цены';
    return [
      '${money(price)} / ${p.unit}',
      if (p.perBox > 1) '${p.perBox} ${p.unit} в кор',
    ].join(' · ');
  }

  String? _tag(Product p) {
    if (_return) {
      final r = widget.inReturn[p.id];
      return r == null ? null : 'в возврате ${r.qty} ${p.unit}';
    }
    final q = widget.inOrder[p.id];
    if (q == null) return null;
    return p.perBox > 1 && q % p.perBox == 0 ? 'в заказе ${q ~/ p.perBox} кор' : 'в заказе $q ${p.unit}';
  }

  void _mode(bool toReturn) => setState(() {
        _return = toReturn;
        _n = 1;
      });

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = widget.data.products.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.barcode == q).toList();
    final sel = _selected;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration:
                      const BoxDecoration(color: Color(0xFFD5D9E0), borderRadius: BorderRadius.all(Radius.circular(3))),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                const Expanded(
                    child: Text('Добавить товар', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(
                  tooltip: 'Закрыть',
                  style: IconButton.styleFrom(backgroundColor: AppColors.fill),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ]),
              const SizedBox(height: 10),
              PillTabs(labels: const ['В заказ', 'В возврат'], index: _return ? 1 : 0, onChanged: (i) => _mode(i == 1)),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Поиск товара',
                  filled: true,
                  fillColor: AppColors.fill,
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Такого товара нет в каталоге',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.text2)),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  children: [for (final p in list) _row(p)],
                ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: sel == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Выберите товар в списке', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2)),
                    )
                  : _chosen(sel),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(Product p) {
    final on = p.id == _selected?.id;
    final tag = _tag(p);
    final noPrice = _price(p) == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: on ? AppColors.accentSoft : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: noPrice
              ? null
              : () => setState(() {
                    _selected = p;
                    _n = 1;
                  }),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 62),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                ProductAvatar(id: p.id, name: p.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(_meta(p),
                          style: TextStyle(
                              fontSize: 13, color: noPrice ? AppColors.err : AppColors.text2, fontFeatures: tabular)),
                    ],
                  ),
                ),
                if (tag != null) ...[
                  const SizedBox(width: 8),
                  _return ? Tag.warn(tag) : Tag(tag),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chosen(Product p) {
    final pieces = _pieces(p), sum = pieces * _price(p);
    final unit = _unit(p);
    final ctaColor = _return ? AppColors.warn : AppColors.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          ProductAvatar(id: p.id, name: p.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(_meta(p), style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (_return)
          ReasonChips(
              reasons: ReturnItem.reasons, value: _reason, height: 34, onChanged: (r) => setState(() => _reason = r))
        else if (_byBox(p))
          Row(children: [
            for (final n in [1, 2, 3]) ...[
              if (n > 1) const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _n = n),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: EdgeInsets.zero,
                    foregroundColor: AppColors.text,
                    side: BorderSide(color: _n == n ? AppColors.accent : AppColors.field),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: Text('$n кор'),
                ),
              ),
            ],
          ]),
        const SizedBox(height: 10),
        Row(children: [
          PillStepper(
            large: true,
            text: '$_n $unit',
            decLabel: 'Меньше',
            incLabel: 'Больше',
            onDec: _n <= 1 ? null : () => setState(() => _n--),
            onInc: _n >= 999 ? null : () => setState(() => _n++),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_return ? 'вычтется из заказа' : '$pieces ${p.unit}',
                  style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
              Text(_return ? '−${money(sum)}' : money(sum),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _return ? AppColors.warn : AppColors.text,
                      fontFeatures: tabular)),
            ],
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ctaColor,
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          onPressed: () => Navigator.pop(
              context, PickedProduct(product: p, toReturn: _return, qty: pieces, reason: _return ? _reason : null)),
          child: Text('${_return ? 'В возврат' : 'В заказ'} · $_n $unit'),
        ),
      ],
    );
  }
}
