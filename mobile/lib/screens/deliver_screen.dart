import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/expeditor_data.dart';
import '../deliveries.dart';
import '../format.dart';
import '../theme.dart';

/// «Выдача» заказа: сколько выдать по каждому товару (сначала — всё по заказу), сколько получено наличными и
/// Kaspi (сначала — как оплачивает магазин); не хватило денег — остаток уходит в долг магазина. Выдано —
/// возвращает true.
class DeliverScreen extends StatefulWidget {
  const DeliverScreen(
      {super.key, required this.trip, required this.stop, required this.settings, required this.deliveries});

  final TripInfo trip;
  final Stop stop;
  final ExpeditorSettings settings;
  final DeliveryBook deliveries;

  @override
  State<DeliverScreen> createState() => _DeliverScreenState();
}

class _DeliverScreenState extends State<DeliverScreen> {
  late final _qty = {for (final l in widget.stop.order.lines) l.productId: l.qty};
  final _cash = TextEditingController();
  final _kaspi = TextEditingController();

  /// Деньги поправили руками — больше не подставляем их по сумме выдачи.
  bool _payTouched = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _cash.dispose();
    _kaspi.dispose();
    super.dispose();
  }

  bool get _kaspiField => widget.settings.acceptKaspi;

  int get _total => widget.stop.order.lines.fold(0, (s, l) => s + (_qty[l.productId] ?? 0) * l.price);
  static int _value(TextEditingController c) => int.tryParse(c.text) ?? 0;
  int get _paid => _value(_cash) + (_kaspiField ? _value(_kaspi) : 0);

  /// Деньги по способу оплаты заказа: наличные или Kaspi — вся сумма, в долг — ничего.
  void _prefill() {
    if (_payTouched) return;
    final total = _total;
    final payment = widget.stop.order.payment;
    final kaspi = payment == 'KASPI' && _kaspiField;
    _cash.text = payment == 'CREDIT' || kaspi || total == 0 ? '' : '$total';
    _kaspi.text = kaspi && total > 0 ? '$total' : '';
  }

  void _setQty(int productId, int qty) => setState(() {
        _qty[productId] = qty;
        _prefill();
      });

  Future<void> _enterQty(TripLine l) async {
    final n = await showDialog<int>(context: context, builder: (_) => _QtyDialog(line: l, qty: _qty[l.productId] ?? 0));
    if (n != null) _setQty(l.productId, n.clamp(0, l.qty));
  }

  Future<void> _deliver() async {
    setState(() => _busy = true);
    final problem = await widget.deliveries.deliver(widget.trip, widget.stop,
        items: {..._qty}, cash: _value(_cash), kaspi: _kaspiField ? _value(_kaspi) : 0, settings: widget.settings);
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
    final order = widget.stop.order;
    final total = _total, paid = _paid;
    final all = order.lines.every((l) => _qty[l.productId] == l.qty);
    final unpaid = total - paid;
    return Scaffold(
      appBar: AppBar(title: Text('Выдача ${order.number}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
                '${widget.stop.outlet.name} · ${order.paymentLabel}'
                '${all ? '' : ' · выдаётся не всё'}',
                style: const TextStyle(color: AppColors.inkSoft)),
          ),
          for (final l in order.lines)
            _LineRow(
                line: l,
                qty: _qty[l.productId] ?? 0,
                onChanged: (q) => _setQty(l.productId, q),
                onEnter: () => _enterQty(l)),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Expanded(child: Text('Выдаётся', style: TextStyle(fontWeight: FontWeight.w600))),
              Text(money(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (!all)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Text('по заказу ${money(order.total)}',
                  textAlign: TextAlign.end, style: const TextStyle(color: AppColors.inkSoft)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Получено', style: TextStyle(color: AppColors.inkSoft)),
                const SizedBox(height: 8),
                _MoneyField(controller: _cash, label: 'Наличными', onChanged: () => setState(() => _payTouched = true)),
                if (_kaspiField) ...[
                  const SizedBox(height: 8),
                  _MoneyField(controller: _kaspi, label: 'Kaspi', onChanged: () => setState(() => _payTouched = true)),
                ],
                const SizedBox(height: 8),
                if (paid > total)
                  Text('Получено больше, чем выдаётся, на ${money(paid - total)}',
                      style: const TextStyle(color: AppColors.crimson))
                else if (unpaid > 0)
                  Text('Остаток ${money(unpaid)} — в долг магазина',
                      style: TextStyle(color: order.payment == 'CREDIT' ? AppColors.ink : AppColors.crimson)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || total == 0 || paid > total ? null : _deliver,
                  child: Text(_busy ? 'Сохраняю…' : 'Выдать на ${money(total)}'),
                ),
                if (total == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Ничего не выдаётся — вернитесь и отметьте отказ',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkSoft)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.qty, required this.onChanged, required this.onEnter});

  final TripLine line;
  final int qty;
  final ValueChanged<int> onChanged;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final l = line;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                Text('заказано ${l.qty} ${l.unit} × ${money(l.price)}',
                    style: TextStyle(color: qty == l.qty ? AppColors.inkSoft : AppColors.crimson)),
                Text('= ${money(qty * l.price)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(tooltip: 'Меньше', onPressed: qty > 0 ? () => onChanged(qty - 1) : null, icon: const Icon(Icons.remove)),
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
          IconButton(
              tooltip: 'Больше', onPressed: qty < l.qty ? () => onChanged(qty + 1) : null, icon: const Icon(Icons.add)),
        ],
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label, required this.onChanged});

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
        decoration: InputDecoration(labelText: label, suffixText: '₸', hintText: '0'),
        onChanged: (_) => onChanged(),
      );
}

/// Сколько выдать числом — не больше заказанного.
class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.line, required this.qty});

  final TripLine line;
  final int qty;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _c = TextEditingController(text: '${widget.qty}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_c.text) ?? 0;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.line.name),
        content: TextField(
          controller: _c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
          decoration: InputDecoration(labelText: 'Выдать, ${widget.line.unit} (заказано ${widget.line.qty})'),
          onSubmitted: (_) => Navigator.pop(context, _value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, _value), child: const Text('Готово')),
        ],
      );
}
