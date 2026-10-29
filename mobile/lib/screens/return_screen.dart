import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/agent_data.dart';
import '../data/expeditor_data.dart';
import '../deliveries.dart';
import '../format.dart';
import '../theme.dart';

/// «Возврат» негодного товара у магазина: товары и штуки — сначала из заказа магазина, поиск по остальным. Сумма — по ценам магазина на день данных; точную по цене дня
/// возврата посчитает сервер. Записано — возвращает true.
class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key, required this.trip, required this.stop, required this.data, required this.deliveries});

  final TripInfo trip;
  final Stop stop;
  final ExpeditorData data;
  final DeliveryBook deliveries;

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _qty = <int, int>{};
  String _query = '';
  bool _busy = false;

  int _price(Product p) => p.priceFor(widget.stop.outlet.priceKind);

  int get _total => _qty.entries.fold(0, (sum, e) {
        final p = widget.data.products.where((x) => x.id == e.key).firstOrNull;
        return sum + (p == null ? 0 : _price(p) * e.value);
      });

  /// Сначала товары из заказа магазина, потом остальные по названию.
  List<Product> get _products {
    final inOrder = {for (final l in widget.stop.order.lines) l.productId};
    final q = _query.trim().toLowerCase();
    return widget.data.products.where((p) => q.isEmpty || p.name.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final byOrder = (inOrder.contains(a.id) ? 0 : 1).compareTo(inOrder.contains(b.id) ? 0 : 1);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
  }

  void _set(Product p, int n) => setState(() {
        if (n <= 0) {
          _qty.remove(p.id);
        } else {
          _qty[p.id] = n;
        }
      });

  Future<void> _enter(Product p) async {
    final c = TextEditingController(text: '${_qty[p.id] ?? ''}');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
          decoration: InputDecoration(labelText: 'Вернули, ${p.unit}'),
          onSubmitted: (_) => Navigator.pop(ctx, int.tryParse(c.text) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text) ?? 0), child: const Text('Готово')),
        ],
      ),
    );
    c.dispose();
    if (n != null) _set(p, n);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final problem =
        await widget.deliveries.returnGoods(widget.trip, widget.stop, items: {..._qty}, total: _total);
    if (!mounted) return;
    setState(() => _busy = false);
    if (problem == null) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.stop.outlet;
    final products = _products;
    final qty = _qty.values.fold(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Возврат', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('${o.name} · ${o.priceLabel.toLowerCase()}',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск товара'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Ничего не найдено', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2)),
                  ),
                for (final p in products)
                  _ReturnRow(
                      product: p,
                      price: _price(p),
                      qty: _qty[p.id] ?? 0,
                      onChanged: (n) => _set(p, n),
                      onEnter: () => _enter(p)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(qty == 0 ? 'Товары не выбраны' : '$qty шт · долг меньше на',
                        style: const TextStyle(color: AppColors.text2)),
                    Text(money(_total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              SizedBox(
                width: 150,
                child: FilledButton(onPressed: _busy || qty == 0 ? null : _save, child: const Text('Принять')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReturnRow extends StatelessWidget {
  const _ReturnRow(
      {required this.product, required this.price, required this.qty, required this.onChanged, required this.onEnter});

  final Product product;
  final int price;
  final int qty;
  final ValueChanged<int> onChanged;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                Text(price == 0 ? 'нет цены' : money(price),
                    style: TextStyle(color: price == 0 ? AppColors.err : AppColors.text2)),
                if (qty > 0) Text('= ${money(price * qty)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (price > 0 && qty == 0)
            IconButton.filledTonal(tooltip: 'Вернуть ${p.name}', onPressed: () => onChanged(1), icon: const Icon(Icons.add))
          else if (price > 0) ...[
            IconButton(tooltip: 'Меньше', onPressed: () => onChanged(qty - 1), icon: const Icon(Icons.remove)),
            InkWell(
              onTap: onEnter,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
                child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            IconButton(tooltip: 'Больше', onPressed: () => onChanged(qty + 1), icon: const Icon(Icons.add)),
          ],
        ],
      ),
    );
  }
}
