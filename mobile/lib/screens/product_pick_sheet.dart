import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../data/order.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/layout.dart';

/// Что выбрали в «Добавить товар»: товар в заказ ([toReturn] = false) или в возврат. Сколько — спросит экран заказа.
class PickedProduct {
  const PickedProduct({required this.product, required this.toReturn});

  final Product product;
  final bool toReturn;
}

/// «Добавить товар» по макету AgentProductPick — лист снизу: «В заказ» / «В возврат», поиск по каталогу, товар
/// с отметкой, сколько его уже в заказе или возврате. Касание товара закрывает лист — количество в штуках
/// вводится уже в окне экрана заказа, клавиатура поиска ему не мешает.
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

  int _price(Product p) => p.priceFor(widget.outlet.priceKind);

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
    return q == null ? null : 'в заказе $q ${p.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = widget.data.products.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.barcode == q).toList();
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
              PillTabs(labels: const ['В заказ', 'В возврат'], index: _return ? 1 : 0, onChanged: (i) => setState(() => _return = i == 1)),
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
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [for (final p in list) _row(p)],
                ),
        ),
      ],
    );
  }

  Widget _row(Product p) {
    final tag = _tag(p);
    final noPrice = _price(p) == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: noPrice ? null : () => Navigator.pop(context, PickedProduct(product: p, toReturn: _return)),
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
}
