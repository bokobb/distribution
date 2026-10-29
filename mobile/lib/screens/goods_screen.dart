import 'package:flutter/material.dart';

import '../data/defect_return.dart';
import '../data/expeditor_data.dart';
import '../deliveries.dart';
import '../format.dart';
import '../invoice.dart';
import '../launch.dart';
import '../theme.dart';
import '../workday.dart';
import 'invoice_screen.dart';
import 'return_screen.dart';
import 'stop_screen.dart';

/// «Состав» заказа по макету ExpDelivery: что отдаём магазину — по коробкам (не кратно коробке — по штуке), не
/// больше заказанного; изменённая строка — янтарная, с тем, сколько было. «Забираем негодный товар» — возвраты
/// у этого магазина сегодня, «Добавить» — экран возврата. Внизу — сколько к оплате: товар минус возврат.
/// «Готово» возвращает, сколько выдать по товарам (id → штук).
class GoodsScreen extends StatefulWidget {
  const GoodsScreen(
      {super.key,
      required this.stop,
      required this.trip,
      required this.data,
      required this.deliveries,
      required this.workday,
      this.expeditor,
      this.plan});

  final Stop stop;
  final TripInfo trip;
  final ExpeditorData data;
  final DeliveryBook deliveries;
  final Workday workday;
  final String? expeditor;

  /// Как поправили в прошлый раз; null — всё по заказу.
  final Map<int, int>? plan;

  @override
  State<GoodsScreen> createState() => _GoodsScreenState();
}

class _GoodsScreenState extends State<GoodsScreen> {
  late final Map<int, int> _qty = {
    for (final l in widget.stop.order.lines) l.productId: widget.plan?[l.productId] ?? l.qty,
  };

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// По коробке, пока выходит ровно; иначе по штуке.
  static int _step(TripLine l, int qty) => l.perBox > 1 && qty % l.perBox == 0 ? l.perBox : 1;

  static String _label(TripLine l, int qty) =>
      l.perBox > 1 && qty % l.perBox == 0 && qty > 0 ? '${qty ~/ l.perBox} кор' : '$qty ${l.unit}';

  int get _goods => widget.stop.order.lines.fold(0, (a, l) => a + (_qty[l.productId] ?? 0) * l.price);

  Future<void> _addReturn() async {
    if (!widget.workday.open) return _say(startDayFirst);
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => ReturnScreen(
                trip: widget.trip, stop: widget.stop, data: widget.data, deliveries: widget.deliveries)));
    if (ok == true && mounted) _say('Возврат сохранён');
  }

  Future<void> _cancelReturn(DefectReturn r) async {
    if (r.sent) return _say('Уже отправлено на сервер — отменить может только оператор');
    final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Отменить возврат?'),
            content: Text('${r.qty} шт на ${money(r.total)} — запись ещё не ушла на сервер, она сотрётся с телефона.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Нет')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Отменить')),
            ],
          ),
        ) ==
        true;
    if (!yes) return;
    final ok = await widget.deliveries.cancelReturn(r);
    if (mounted && !ok) _say('Уже отправлено на сервер — отменить может только оператор');
  }

  void _done() {
    if (_qty.values.every((q) => q == 0)) {
      return _say('Ничего не выдаётся — если магазин не берёт заказ, отметьте «Магазин отказался»');
    }
    Navigator.pop(context, {..._qty});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stop, o = s.outlet, order = s.order;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Заказ ${order.number}'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Накладная',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => InvoiceScreen(
                        invoice: Invoice.of(
                            data: widget.data, trip: widget.trip, stop: s, local: null, expeditor: widget.expeditor)))),
          ),
          if (o.phone != null)
            IconButton(
                tooltip: 'Позвонить в магазин',
                icon: const Icon(Icons.call_outlined),
                onPressed: () => call(context, o.phone!)),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.deliveries,
        builder: (context, _) {
          final returns = widget.deliveries.returnsAt(o.id);
          final back = returns.where((r) => r.error == null).fold(0, (a, r) => a + r.total);
          final goods = _goods;
          final toPay = (goods - back - order.paid).clamp(0, 1 << 40);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.name, style: text.headlineSmall),
                          Text([o.address ?? o.landmark, order.agent].nonNulls.join(' · '),
                              style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                        ],
                      ),
                    ),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _head('Отдаём магазину',
                              trailing: Text(plural(order.lines.length, 'позиция', 'позиции', 'позиций'),
                                  style: const TextStyle(fontSize: 13, color: AppColors.text2))),
                          for (final l in order.lines) _line(l),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _head('Забираем негодный товар',
                              trailing: TextButton.icon(
                                onPressed: _addReturn,
                                style: TextButton.styleFrom(
                                    foregroundColor: AppColors.accent,
                                    minimumSize: const Size(0, 36),
                                    textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Добавить'),
                              )),
                          if (returns.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                              child: Text('Если магазин отдаёт брак или просрочку — добавьте, сумма вычтется из оплаты.',
                                  style: TextStyle(fontSize: 13, color: AppColors.text2)),
                            ),
                          for (final r in returns)
                            for (final e in r.items.entries) _returnLine(r, e.key, e.value),
                          if (returns.isNotEmpty) const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  back == 0 && order.paid == 0
                                      ? 'К оплате'
                                      : [
                                          amount(goods),
                                          if (back > 0) 'возврат ${amount(back)}',
                                          if (order.paid > 0) 'оплачено ${amount(order.paid)}',
                                        ].join(' − '),
                                  style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
                              FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(money(toPay), style: text.headlineSmall)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _done,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 26)),
                          child: const Text('Готово'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _head(String title, {required Widget trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: SizedBox(
          height: 36,
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Padding(padding: const EdgeInsets.only(right: 8), child: trailing),
          ]),
        ),
      );

  Widget _line(TripLine l) {
    final qty = _qty[l.productId] ?? 0;
    final changed = qty != l.qty;
    final step = _step(l, qty);
    final down = qty == 0 ? 0 : step;
    final up = qty >= l.qty ? 0 : step;
    final byBox = step > 1;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: changed ? const Color(0xFFFFFAF0) : null,
        border: const Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(
                    changed
                        ? 'было ${_label(l, l.qty)} · сейчас $qty ${l.unit} · ${money(qty * l.price)}'
                        : '$qty ${l.unit} · ${money(qty * l.price)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: changed ? FontWeight.w600 : FontWeight.w400,
                        color: changed ? const Color(0xFF8A5000) : AppColors.text2,
                        fontFeatures: tabular)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              border: Border.all(color: changed ? AppColors.accent : AppColors.field, width: changed ? 1.5 : 1),
            ),
            child: Row(children: [
              _stepButton(Icons.remove, down == 0 ? null : () => setState(() => _qty[l.productId] = qty - down),
                  byBox ? 'Меньше на коробку' : 'Меньше на штуку'),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 50),
                child: Text(_label(l, qty),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: changed ? FontWeight.w700 : FontWeight.w600,
                        color: changed ? AppColors.accentPressed : AppColors.text,
                        fontFeatures: tabular)),
              ),
              _stepButton(Icons.add, up == 0 ? null : () => setState(() => _qty[l.productId] = (qty + up).clamp(0, l.qty)),
                  byBox ? 'Больше на коробку' : 'Больше на штуку'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap, String tooltip) => SizedBox(
        width: 40,
        height: 42,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          color: AppColors.text,
          disabledColor: const Color(0xFFC9CDD5),
        ),
      );

  Widget _returnLine(DefectReturn r, int productId, int qty) {
    final p = widget.data.products.where((x) => x.id == productId).firstOrNull;
    final line = widget.stop.order.lines.where((l) => l.productId == productId).firstOrNull;
    final name = p?.name ?? line?.name ?? 'Товар $productId';
    final price = p?.priceFor(widget.stop.outlet.priceKind) ?? line?.price ?? 0;
    final note = r.error != null
        ? 'сервер не принял: ${r.error}'
        : r.sent
            ? r.reasonLabel.toLowerCase()
            : '${r.reasonLabel.toLowerCase()} · ждёт отправки';
    return InkWell(
      onTap: r.sent ? null : () => _cancelReturn(r),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text('$qty шт · $note',
                    style: TextStyle(fontSize: 13, color: r.error != null ? AppColors.err : AppColors.text2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('−${money(price * qty)}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text2, fontFeatures: tabular)),
        ]),
      ),
    );
  }
}
