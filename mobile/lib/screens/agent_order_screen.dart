import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/agent_data.dart';
import '../data/order.dart';
import '../format.dart';
import '../geo.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/layout.dart';
import 'checkout_screen.dart';
import 'no_order_screen.dart';
import 'product_pick_sheet.dart';

/// Заказ и возврат на одном экране по макету AgentOrder — во время визита в магазин. Вверху долг своего магазина
/// (лимит, просрочка). «Заказ · N»: товары по штукам, «Как 21 октября» — повторить прошлый заказ, «Добавить
/// позицию». «Возврат · N»: негодный товар, который магазин отдаёт, по штукам с причиной — экспедитор заберёт при
/// доставке, сумма вычтется. Внизу — заказ минус возврат и «Далее» к оформлению. Всё сразу пишется черновиком на
/// телефон: приложение закрылось — товары на месте. «Без заказа» — закончить визит с причиной. Отправили заказ
/// или закончили без заказа — возвращает true. С [editing] — правка уже взятого заказа (из «Визитов сегодня» или
/// «Заказов»): его товары и возврат, без визита и черновика; сохранили — true.
class AgentOrderScreen extends StatefulWidget {
  const AgentOrderScreen({super.key, required this.outlet, required this.data, required this.visits, this.editing});

  final Outlet outlet;
  final AgentData data;
  final VisitBook visits;
  final Order? editing;

  @override
  State<AgentOrderScreen> createState() => _AgentOrderScreenState();
}

class _AgentOrderScreenState extends State<AgentOrderScreen> {
  /// id товара → штук, в порядке добавления.
  final _qty = <int, int>{};

  /// id товара → строка возврата.
  final _ret = <int, ReturnItem>{};
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (widget.editing case final o?) {
      _qty.addAll(o.items);
      for (final r in o.returns) {
        _ret[r.productId] = r;
      }
      return;
    }
    widget.visits.draft().then((d) {
      if (!mounted || d.items.isEmpty && d.returns.isEmpty) return;
      setState(() {
        _qty.addAll(d.items);
        for (final r in d.returns) {
          _ret[r.productId] = r;
        }
      });
    });
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  int _price(Product p) => p.priceFor(widget.outlet.priceKind);

  int _sum(Map<int, int> qty) => qty.entries.fold(0, (sum, e) {
        final p = widget.data.product(e.key);
        return sum + (p == null ? 0 : _price(p) * e.value);
      });

  int get _orderSum => _sum(_qty);
  int get _retSum => _sum({for (final r in _ret.values) r.productId: r.qty});

  void _changed() {
    setState(() {});
    if (widget.editing == null) widget.visits.saveDraft(_qty, _ret.values.toList());
  }

  void _setQty(int id, int n) {
    if (n <= 0) {
      _qty.remove(id);
    } else {
      _qty[id] = n;
    }
    _changed();
  }

  void _setRet(int id, int n) {
    if (n <= 0) {
      _ret.remove(id);
    } else {
      _ret[id] = ReturnItem(productId: id, qty: n);
    }
    _changed();
  }

  /// Прошлый заказ магазина — только товары, которые сейчас продаются и с ценой.
  void _repeat(LastOrder last) {
    var skipped = 0;
    _qty.clear();
    for (final e in last.items.entries) {
      final p = widget.data.product(e.key);
      if (p == null || _price(p) == 0) {
        skipped++;
      } else {
        _qty[e.key] = e.value;
      }
    }
    _changed();
    if (skipped > 0) _say('Не добавлено: ${plural(skipped, 'товар', 'товара', 'товаров')} — уже не продаются или нет цены');
  }

  Future<void> _add() async {
    final picked = await pickProduct(context,
        data: widget.data, outlet: widget.outlet, toReturn: _tab == 1, inOrder: _qty, inReturn: _ret);
    if (picked == null || !mounted) return;
    setState(() => _tab = picked.toReturn ? 1 : 0);
    await _enter(picked.product, toReturn: picked.toReturn);
  }

  /// Сколько штук — окном с цифровой клавиатурой.
  Future<void> _enter(Product p, {required bool toReturn}) async {
    final n = await showDialog<int>(
        context: context,
        builder: (_) => _QtyDialog(
            product: p,
            price: _price(p),
            qty: toReturn ? _ret[p.id]?.qty ?? 0 : _qty[p.id] ?? 0,
            toReturn: toReturn));
    if (n == null || !mounted) return;
    if (toReturn) {
      _setRet(p.id, n);
    } else {
      _setQty(p.id, n);
    }
  }

  Future<void> _noOrder() async {
    final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => NoOrderScreen(outlet: widget.outlet, data: widget.data, visits: widget.visits)));
    if (done == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _next() async {
    if (_qty.isEmpty) {
      return _say(_ret.isEmpty
          ? 'Добавьте товары в заказ'
          : 'Возврат экспедитор заберёт вместе с заказом — добавьте товары в заказ');
    }
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          outlet: widget.outlet,
          data: widget.data,
          visits: widget.visits,
          items: {..._qty},
          returns: _ret.values.toList(),
          total: _orderSum,
          returnTotal: _retSum,
          editing: widget.editing,
        ),
      ),
    );
    if (sent == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _cancelVisit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отменить визит?'),
        content: const Text('Визит, заказ и фото будут стёрты, на сервер они не уйдут.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Отменить визит')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.visits.cancel();
    if (mounted) Navigator.pop(context, false);
  }

  /// «вы у магазина · ул. Абая, 41» или «340 м от магазина · …» — главное первым, адрес обрежется. При правке —
  /// какой заказ правится.
  String get _where {
    if (widget.editing case final e?) return 'Изменение заказа ${e.number ?? '(ещё не отправлен)'}';
    final o = widget.outlet, v = widget.visits.current;
    final place = o.address ?? o.landmark;
    final d = v?.distance;
    final at = d == null
        ? null
        : d <= widget.data.settings.visitRadius + VisitBook.accuracyAllowance
            ? 'вы у магазина'
            : '${distanceLabel(d)} от магазина';
    return [?at, ?place].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.outlet;
    final orderSum = _orderSum, retSum = _retSum;
    final pieces = _qty.values.fold(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [
              if (widget.editing == null && widget.visits.current?.distance != null) ...[
                Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(color: AppColors.ok, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(_where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text2)),
              ),
            ]),
          ],
        ),
        actions: [
          if (widget.editing == null) ...[
            TextButton(
              onPressed: _noOrder,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.text2,
                  textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
              child: const Text('Без заказа'),
            ),
            PopupMenuButton<void>(
              tooltip: 'Ещё',
              itemBuilder: (_) => [PopupMenuItem(onTap: _cancelVisit, child: const Text('Отменить визит'))],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_debtCard() case final card?) ...[card, const SizedBox(height: 10)],
                PillTabs(
                  labels: ['Заказ · ${_qty.length}', 'Возврат · ${_ret.length}'],
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: _tab == 0 ? _orderTab(orderSum) : _returnTab(retSum),
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        retSum > 0
                            ? 'Заказ ${amount(orderSum)} − возврат ${amount(retSum)}'
                            : _qty.isEmpty
                                ? 'Товары не выбраны'
                                : '$pieces шт · ${plural(_qty.length, 'позиция', 'позиции', 'позиций')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(money(orderSum - retSum),
                          style: const TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _next,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 22)),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward, size: 20),
                label: const Text('Далее'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Долг своего магазина: сколько из лимита и просрочка. У чужого и без долга — ничего.
  Widget? _debtCard() {
    final o = widget.outlet;
    if (!o.mine || o.debt <= 0 && o.overdue <= 0) return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: const BoxDecoration(
          color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(14)), boxShadow: cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Долг ${money(o.debt)}'),
              if (o.creditLimit > 0)
                TextSpan(
                    text: ' из ${money(o.creditLimit)}',
                    style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.text2)),
            ]),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: o.overLimit ? AppColors.err : AppColors.text,
                fontFeatures: tabular),
          ),
          if (o.overdue > 0)
            Text('Просрочено ${money(o.overdue)}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF8A5000), fontFeatures: tabular)),
        ],
      ),
    );
  }

  Widget _head(String title, String sum, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$title\n'),
            TextSpan(text: 'на сумму $sum', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ]),
          style: const TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, fontFeatures: tabular),
        ),
      );

  List<Widget> _orderTab(int sum) {
    final last = widget.editing == null ? widget.data.lastOrders[widget.outlet.id] : null;
    return [
      _head('${plural(_qty.length, 'товар', 'товара', 'товаров')} в заказе', money(sum), AppColors.text2),
      if (last != null) ...[
        OutlinedButton.icon(
          onPressed: () => _repeat(last),
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.text,
            side: BorderSide.none,
            minimumSize: const Size.fromHeight(40),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
          ),
          icon: const Icon(Icons.replay, size: 18),
          label: Text('Как ${dayMonth(last.date)}'),
        ),
        const SizedBox(height: 12),
      ],
      for (final e in _qty.entries)
        if (widget.data.product(e.key) case final p?) _orderRow(p, e.value),
      _addButton('Добавить позицию', AppColors.accent, AppColors.accent),
    ];
  }

  Widget _orderRow(Product p, int qty) {
    final price = _price(p);
    final last = qty <= 1;
    return _card(
      child: Row(children: [
        ProductAvatar(id: p.id, name: p.name),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: const TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600)),
              Text(
                  [
                    '${money(price)} / ${p.unit}',
                    if (p.perBox > 1) '${p.perBox} ${p.unit} в кор',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.text2, fontFeatures: tabular)),
              Text('$qty ${p.unit} · ${money(price * qty)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: tabular)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PillStepper(
          text: '$qty ${p.unit}',
          removes: last,
          decLabel: last ? 'Убрать из заказа' : 'Убрать штуку',
          incLabel: 'Добавить штуку',
          onDec: () => _setQty(p.id, qty - 1),
          onInc: () => _setQty(p.id, qty + 1),
          onText: () => _enter(p, toReturn: false),
        ),
      ]),
    );
  }

  List<Widget> _returnTab(int sum) => [
        _head('${plural(_ret.length, 'товар', 'товара', 'товаров')} в возврате', '−${money(sum)}', AppColors.warn),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 18, color: AppColors.text2),
            SizedBox(width: 8),
            Expanded(
              child: Text('Экспедитор заберёт этот товар при доставке — сумма вычтется из заказа',
                  style: TextStyle(fontSize: 13, height: 18 / 13, color: AppColors.text2)),
            ),
          ]),
        ),
        if (_ret.isEmpty)
          _card(
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Возврата нет — если магазин отдаёт негодный товар, добавьте его',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.text2)),
            ),
          ),
        for (final r in _ret.values)
          if (widget.data.product(r.productId) case final p?) _returnRow(p, r),
        _addButton('Добавить в возврат', const Color(0xFF8A5000), const Color(0xFFC98A2E)),
      ];

  Widget _returnRow(Product p, ReturnItem r) {
    final price = _price(p);
    return _card(
      child: Row(children: [
        ProductAvatar(id: p.id, name: p.name),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: const TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600)),
              Text('${r.qty} ${p.unit} × ${money(price)} = −${money(price * r.qty)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.warn, fontFeatures: tabular)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PillStepper(
          text: '${r.qty} ${p.unit}',
          removes: r.qty <= 1,
          decLabel: r.qty <= 1 ? 'Убрать из возврата' : 'Убрать штуку',
          incLabel: 'Добавить штуку',
          onDec: () => _setRet(p.id, r.qty - 1),
          onInc: () => _setRet(p.id, r.qty + 1),
          onText: () => _enter(p, toReturn: true),
        ),
      ]),
    );
  }

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );

  Widget _addButton(String label, Color color, Color border) => OutlinedButton.icon(
        onPressed: _add,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: border, width: 1.5),
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
        ),
        icon: const Icon(Icons.add, size: 20),
        label: Text(label),
      );
}

/// Количество в штуках числом: товар добавляют из «Добавить позицию» или правят касанием количества в строке.
/// В заказе — подсказка «+ коробка» и сколько это коробок; в возврате ([toReturn]) — янтарная кнопка. Сумма по прайсу
/// магазина. Было 0 — кнопка «В заказ» / «В возврат», иначе «Готово» (0 — убрать из списка).
class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.product, required this.price, required this.qty, required this.toReturn});

  final Product product;
  final int price;
  final int qty;
  final bool toReturn;

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

  bool get _return => widget.toReturn;

  bool get _ok => _value > 0 || widget.qty > 0;

  void _done() {
    if (_ok) Navigator.pop(context, _value);
  }

  void _box() {
    _c.text = '${_value + widget.product.perBox}';
    _c.selection = TextSelection.collapsed(offset: _c.text.length);
    setState(() {});
  }

  /// «24 шт · 2 кор» или «30 шт · 2 кор + 6 шт».
  String _pieces(Product p, int n) {
    if (p.perBox <= 1 || n < p.perBox) return '$n ${p.unit}';
    final rest = n % p.perBox;
    return '$n ${p.unit} · ${n ~/ p.perBox} кор${rest > 0 ? ' + $rest ${p.unit}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product, n = _value, sum = n * widget.price;
    final label = widget.qty > 0 ? 'Готово' : (_return ? 'В возврат' : 'В заказ');
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
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
                    Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(
                        [
                          '${money(widget.price)} / ${p.unit}',
                          if (p.perBox > 1) '${p.perBox} ${p.unit} в кор',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _c,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: tabular),
              decoration: InputDecoration(labelText: 'Количество, ${p.unit}', suffixText: p.unit),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _done(),
            ),
            if (!_return && p.perBox > 1) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _box,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('коробка (${p.perBox} ${p.unit})'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(n == 0 && widget.qty > 0 ? (_return ? 'убрать из возврата' : 'убрать из заказа') : _pieces(p, n),
                    style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
              ),
              Text(_return ? '−${money(sum)}' : money(sum),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _return ? AppColors.warn : AppColors.text,
                      fontFeatures: tabular)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: _return ? FilledButton.styleFrom(backgroundColor: AppColors.warn) : null,
                  onPressed: _ok ? _done : null,
                  child: Text(label),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
