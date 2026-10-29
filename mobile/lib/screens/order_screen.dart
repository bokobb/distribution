import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/agent_data.dart';
import '../data/order.dart';
import '../format.dart';
import '../theme.dart';
import '../visits.dart';

/// Заказ во время визита: товары по категориям с поиском, количество, цены по прайсу магазина на день
/// синхронизации; «Оформить» — оплата, дата доставки, комментарий. Выбранное сразу пишется черновиком на
/// телефон: приложение закрылось — товары на месте. Сохранённый заказ заканчивает визит.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.outlet, required this.data, required this.visits});

  final Outlet outlet;
  final AgentData data;
  final VisitBook visits;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Map<int, int> _qty = {};
  String _query = '';
  bool _onlyChosen = false;

  @override
  void initState() {
    super.initState();
    widget.visits.draft().then((d) {
      if (mounted && d.isNotEmpty) setState(() => _qty = d);
    });
  }

  int _price(Product p) => p.priceFor(widget.outlet.priceKind);

  int get _total => _qty.entries.fold(0, (sum, e) {
        final p = widget.data.product(e.key);
        return sum + (p == null ? 0 : _price(p) * e.value);
      });

  void _set(Product p, int n) {
    setState(() {
      if (n <= 0) {
        _qty.remove(p.id);
      } else {
        _qty[p.id] = n;
      }
      if (_qty.isEmpty) _onlyChosen = false;
    });
    widget.visits.saveDraft(_qty);
  }

  Future<void> _enter(Product p) async {
    final n = await showDialog<int>(context: context, builder: (_) => _QtyDialog(product: p, qty: _qty[p.id] ?? 0));
    if (n != null) _set(p, n);
  }

  Future<void> _checkout() async {
    final total = _total;
    final done = await showModalBottomSheet<_Checkout>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CheckoutSheet(outlet: widget.outlet, settings: widget.data.settings, total: total, lines: _qty.length),
    );
    if (done == null || !mounted) return;
    final problem = await widget.visits.finishWithOrder(
      items: _qty,
      total: total,
      payment: done.payment,
      deliveryDate: done.delivery,
      comment: done.comment,
      settings: widget.data.settings,
    );
    if (!mounted) return;
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = widget.data.products.where((p) {
      if (_onlyChosen && !_qty.containsKey(p.id)) return false;
      return q.isEmpty || p.name.toLowerCase().contains(q) || p.barcode == q;
    });
    final byCategory = <String, List<Product>>{};
    for (final p in shown) {
      byCategory.putIfAbsent(p.category, () => []).add(p);
    }
    final categories = byCategory.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Заказ', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('${widget.outlet.name} · ${widget.outlet.priceLabel.toLowerCase()}',
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
          if (_qty.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: Text('Только выбранные: ${_qty.length}'),
                  selected: _onlyChosen,
                  onSelected: (v) => setState(() => _onlyChosen = v),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Ничего не найдено', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2)),
                  ),
                for (final c in categories) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(c, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text2)),
                  ),
                  for (final p in byCategory[c]!)
                    _ProductRow(
                      product: p,
                      price: _price(p),
                      qty: _qty[p.id] ?? 0,
                      onChanged: (n) => _set(p, n),
                      onEnter: () => _enter(p),
                    ),
                ],
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
                    Text(_qty.isEmpty ? 'Товары не выбраны' : plural(_qty.length, 'товар', 'товара', 'товаров'),
                        style: const TextStyle(color: AppColors.text2)),
                    Text(money(_total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              SizedBox(
                width: 150,
                child: FilledButton(onPressed: _qty.isEmpty ? null : _checkout, child: const Text('Оформить')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow(
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
                Text(price == 0 ? 'нет цены' : '${money(price)} · в коробке ${p.perBox} ${p.unit}',
                    style: TextStyle(color: price == 0 ? AppColors.err : AppColors.text2)),
                if (qty > 0) Text('= ${money(price * qty)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (price > 0 && qty == 0)
            IconButton.filledTonal(tooltip: 'Добавить ${p.name}', onPressed: () => onChanged(1), icon: const Icon(Icons.add))
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

/// Количество числом; «+ коробка» — добавить штук на коробку.
class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.product, required this.qty});

  final Product product;
  final int qty;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _c = TextEditingController(text: widget.qty == 0 ? '' : '${widget.qty}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_c.text) ?? 0;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _c,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              decoration: InputDecoration(labelText: 'Количество, ${widget.product.unit}'),
              onSubmitted: (_) => Navigator.pop(context, _value),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _c.text = '${_value + widget.product.perBox}'),
              child: Text('+ коробка (${widget.product.perBox} ${widget.product.unit})'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, _value), child: const Text('Готово')),
        ],
      );
}

class _Checkout {
  const _Checkout(this.payment, this.delivery, this.comment);

  final String payment;
  final DateTime delivery;
  final String? comment;
}

/// Оформление: оплата (что разрешено в настройках), дата доставки, комментарий; в долг сверх лимита —
/// предупреждение, что заказ уйдёт на разрешение.
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.outlet, required this.settings, required this.total, required this.lines});

  final Outlet outlet;
  final AgentSettings settings;
  final int total;
  final int lines;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  String _payment = 'CASH';
  late DateTime _delivery = _today().add(Duration(days: widget.settings.deliveryDays));
  final _comment = TextEditingController();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  List<String> get _payments => [
        'CASH',
        if (widget.settings.acceptKaspi) 'KASPI',
        if (widget.settings.allowCredit) 'CREDIT',
      ];

  /// В долг сверх лимита магазина — по долгу на день синхронизации.
  String? get _limitNote {
    final o = widget.outlet;
    if (_payment != 'CREDIT' || o.creditLimit == 0 || o.debt + widget.total <= o.creditLimit) return null;
    final text = 'Долг ${money(o.debt)} + заказ ${money(widget.total)} больше лимита ${money(o.creditLimit)}';
    return widget.settings.approvalOverLimit ? '$text — заказ уйдёт на разрешение оператору' : text;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _delivery,
      firstDate: _today(),
      lastDate: _today().add(const Duration(days: 14)),
      helpText: 'Дата доставки',
    );
    if (d != null) setState(() => _delivery = d);
  }

  @override
  Widget build(BuildContext context) {
    final note = _limitNote;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${plural(widget.lines, 'товар', 'товара', 'товаров')} на ${money(widget.total)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text('Оплата', style: TextStyle(color: AppColors.text2)),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in _payments)
                    ChoiceChip(
                      label: Text(Order.paymentLabels[p]!),
                      selected: _payment == p,
                      onSelected: (_) => setState(() => _payment = p),
                    ),
                ],
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(note, style: const TextStyle(color: AppColors.err)),
                ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_shipping_outlined),
                title: const Text('Доставка'),
                subtitle: Text('${weekdaysShort[_delivery.weekday - 1]}, ${date(_delivery)}'),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDate,
              ),
              TextField(
                controller: _comment,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Комментарий (необязательно)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _Checkout(_payment, _delivery, _comment.text)),
                child: const Text('Сохранить заказ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
