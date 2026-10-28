import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/debt_payment.dart';
import '../data/defect_return.dart';
import '../data/delivery.dart';
import '../data/expeditor_data.dart';
import '../deliveries.dart';
import '../format.dart';
import '../invoice.dart';
import '../launch.dart';
import '../theme.dart';
import '../workday.dart';
import 'deliver_screen.dart';
import 'invoice_screen.dart';
import 'return_screen.dart';

/// Точка рейса: что везём (заказ с составом и суммой, как оплачивает), магазин — долг, телефон, адрес;
/// «Позвонить» и «Маршрут» (карты на телефоне). «Выдать» (всё или часть, с деньгами), «Отказ» с причиной,
/// «Оплата долга» и «Возврат» негодного — в открытый рабочий день; что ещё не ушло на сервер, можно отменить.
class StopScreen extends StatefulWidget {
  const StopScreen(
      {super.key,
      required this.stop,
      required this.trip,
      required this.data,
      required this.deliveries,
      required this.workday,
      this.expeditor});

  final Stop stop;
  final TripInfo trip;
  final ExpeditorData data;
  final DeliveryBook deliveries;
  final Workday workday;

  /// Кто везёт — для накладной.
  final String? expeditor;

  @override
  State<StopScreen> createState() => _StopScreenState();
}

class _StopScreenState extends State<StopScreen> {
  bool _busy = false;

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Рейс отгружен на следующий день — выдавать рано.
  bool get _ahead => widget.trip.date.isAfter(widget.data.date);

  bool _canAct() {
    if (!widget.workday.open) {
      _say('Сначала начните рабочий день на главном экране');
      return false;
    }
    return true;
  }

  Future<void> _deliver() async {
    if (!_canAct()) return;
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => DeliverScreen(
                trip: widget.trip, stop: widget.stop, settings: widget.data.settings, deliveries: widget.deliveries)));
    if (ok == true && mounted) _say('Выдача сохранена');
  }

  Future<void> _refuse() async {
    if (!_canAct()) return;
    final reason = await showDialog<String>(context: context, builder: (_) => const _RefuseDialog());
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final problem = await widget.deliveries.refuse(widget.trip, widget.stop, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(problem ?? 'Отказ сохранён');
  }

  Future<void> _cancel(Delivery d) async {
    final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(d.refused ? 'Отменить отказ?' : 'Отменить выдачу?'),
            content: const Text('Запись ещё не ушла на сервер — она сотрётся с телефона, заказ снова можно выдать.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Нет')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Отменить')),
            ],
          ),
        ) ==
        true;
    if (!yes) return;
    final ok = await widget.deliveries.cancel(d);
    if (mounted && !ok) _say('Уже отправлено на сервер — отменить может только оператор');
  }

  Future<void> _payDebt() async {
    if (!_canAct()) return;
    final got = await showDialog<(int, int)>(
        context: context,
        builder: (_) => _DebtDialog(debt: widget.stop.outlet.debt, acceptKaspi: widget.data.settings.acceptKaspi));
    if (got == null || !mounted) return;
    final problem = await widget.deliveries
        .payDebt(widget.trip, widget.stop, cash: got.$1, kaspi: got.$2, settings: widget.data.settings);
    if (mounted) _say(problem ?? 'Оплата долга сохранена');
  }

  Future<void> _return() async {
    if (!_canAct()) return;
    final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => ReturnScreen(
                trip: widget.trip, stop: widget.stop, data: widget.data, deliveries: widget.deliveries)));
    if (ok == true && mounted) _say('Возврат сохранён');
  }

  Future<void> _cancelReturn(DefectReturn r) async {
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

  Future<void> _cancelPayment(DebtPayment p) async {
    final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Отменить оплату долга?'),
            content: Text('${money(p.amount)} ${p.methodLabel} — запись ещё не ушла на сервер, она сотрётся с телефона.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Нет')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Отменить')),
            ],
          ),
        ) ==
        true;
    if (!yes) return;
    final ok = await widget.deliveries.cancelPayment(p);
    if (mounted && !ok) _say('Уже отправлено на сервер — отменить может только оператор');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.deliveries, builder: (context, _) => _page());

  Widget _page() {
    final stop = widget.stop, data = widget.data;
    final o = stop.outlet;
    final order = stop.order;
    final local = widget.deliveries.of(order.id);
    final done = widget.deliveries.done(order);
    final hasPlace = o.lat != null && o.lng != null || o.address != null || o.landmark != null;
    final refused = order.refused || local != null && local.error == null && local.refused;
    return Scaffold(
      appBar: AppBar(
        title: Text(o.name),
        actions: [
          if (!refused)
            IconButton(
              tooltip: 'Накладная',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => InvoiceScreen(
                          invoice: Invoice.of(
                              data: data, trip: widget.trip, stop: stop, local: local, expeditor: widget.expeditor)))),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              if (o.phone != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => call(context, o.phone!),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Позвонить'),
                  ),
                ),
              if (o.phone != null && hasPlace) const SizedBox(width: 8),
              if (hasPlace)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => route(context, lat: o.lat, lng: o.lng, name: o.name, address: o.address ?? o.landmark),
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Маршрут'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (local != null && (!order.done || local.error != null)) ...[
            _DeliveryCard(delivery: local, onCancel: local.sent || local.error != null ? null : () => _cancel(local)),
            const SizedBox(height: 12),
          ],
          if (!done && !_ahead) ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _deliver,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Выдать'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _refuse,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.crimson),
                    child: const Text('Отказ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_ahead)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Рейс на следующий день — выдать можно будет в день доставки.',
                  style: TextStyle(color: AppColors.inkSoft)),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Заказ ${order.number}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text(
                      [
                        order.paymentLabel,
                        'доставка ${date(order.deliveryDate)}',
                        if (order.agent != null) 'принял ${order.agent}',
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.inkSoft)),
                  if (order.done)
                    Text(order.statusLabel, style: TextStyle(color: order.refused ? AppColors.crimson : AppColors.ok)),
                  if (order.comment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Комментарий: ${order.comment}'),
                    ),
                  const Divider(height: 24),
                  for (final l in order.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name),
                                Text(
                                    [
                                      '${l.qty} ${l.unit} × ${money(l.price)}',
                                      if (l.perBox > 1 && l.qty >= l.perBox) _boxes(l),
                                      if (l.delivered != null && l.delivered != l.qty) 'выдано ${l.delivered}',
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                              ],
                            ),
                          ),
                          Text(money(l.sum)),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  Row(children: [
                    const Expanded(child: Text('Итого', style: TextStyle(fontWeight: FontWeight.w600))),
                    Text(money(order.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ]),
                  if (order.paid > 0)
                    Text('Оплачено ${money(order.paid)}', textAlign: TextAlign.end, style: const TextStyle(color: AppColors.ok)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      o.debt == 0
                          ? 'Долга нет'
                          : o.debt < 0
                              ? 'Аванс ${money(-o.debt)}'
                              : 'Долг ${money(o.debt)}',
                      style: TextStyle(fontSize: 16, color: o.overdue > 0 ? AppColors.crimson : AppColors.ink)),
                  if (o.overdue > 0) Text('просрочено ${money(o.overdue)}', style: const TextStyle(color: AppColors.crimson)),
                  Text('на ${date(data.date)}', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                  for (final p in widget.deliveries.paymentsAt(o.id))
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              'Принято в счёт долга ${money(p.amount)} ${p.methodLabel} · ${time(p.paidAt)} · '
                              '${_state(p.sent, p.error, p.debtAfter)}',
                              style: TextStyle(color: p.error != null ? AppColors.crimson : AppColors.ok)),
                        ),
                        if (!p.sent && p.error == null)
                          IconButton(
                              tooltip: 'Отменить оплату',
                              onPressed: () => _cancelPayment(p),
                              icon: const Icon(Icons.undo, size: 20)),
                      ],
                    ),
                  for (final r in widget.deliveries.returnsAt(o.id))
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              'Возврат (${r.reasonLabel.toLowerCase()}) ${r.qty} шт на ${money(r.total)} · '
                              '${time(r.returnedAt)} · ${_state(r.sent, r.error, r.debtAfter)}',
                              style: TextStyle(color: r.error != null ? AppColors.crimson : AppColors.ok)),
                        ),
                        if (!r.sent && r.error == null)
                          IconButton(
                              tooltip: 'Отменить возврат',
                              onPressed: () => _cancelReturn(r),
                              icon: const Icon(Icons.undo, size: 20)),
                      ],
                    ),
                  if (!_ahead)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _payDebt,
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('Оплата долга'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _return,
                            icon: const Icon(Icons.assignment_return_outlined),
                            label: const Text('Возврат'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (o.legal != null) Text(o.legal!),
                  if (o.phone != null) Text(o.phone!),
                  if (o.phone2 != null) Text(o.phone2!),
                  if (o.address != null) Text(o.address!),
                  if (o.landmark != null) Text('Ориентир: ${o.landmark}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Оплата или возврат: ждёт отправки, сервер не принял — почему, принят — какой стал долг.
  static String _state(bool sent, String? error, int? debtAfter) => error != null
      ? 'сервер не принял: $error'
      : !sent
          ? 'ждёт отправки'
          : debtAfter == null
              ? 'отправлено'
              : debtAfter < 0
                  ? 'аванс ${money(-debtAfter)}'
                  : 'долг теперь ${money(debtAfter)}';

  /// «2 кор. + 3 шт».
  static String _boxes(TripLine l) {
    final boxes = l.qty ~/ l.perBox, rest = l.qty % l.perBox;
    return '$boxes кор.${rest > 0 ? ' + $rest ${l.unit}' : ''}';
  }
}

/// Выдача на телефоне: что записано, ушло ли на сервер; не принято — почему.
class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.delivery, this.onCancel});

  final Delivery delivery;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final color = d.error != null || d.refused ? AppColors.crimson : AppColors.ok;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                d.refused
                    ? 'Отказ: ${d.refuseReason}'
                    : '${d.partial ? 'Выдано частично' : 'Выдано всё'} на ${money(d.total)}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color)),
            if (!d.refused)
              Text(
                  [
                    if (d.cash > 0) 'наличными ${money(d.cash)}',
                    if (d.kaspi > 0) 'Kaspi ${money(d.kaspi)}',
                    if (d.paid == 0) 'денег не получено',
                    if (d.unpaid > 0) 'в долг ${money(d.unpaid)}',
                  ].join(' · ')),
            Text(
                d.error != null
                    ? 'Сервер не принял: ${d.error}'
                    : d.sent
                        ? 'Отправлено ${time(d.deliveredAt)}'
                        : 'Ждёт отправки · ${time(d.deliveredAt)}',
                style: TextStyle(fontSize: 13, color: d.error != null ? AppColors.crimson : AppColors.inkSoft)),
            if (d.error != null)
              const Text('Выдайте заново или уберите запись на экране «Отправка».',
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            if (onCancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onCancel, child: Text(d.refused ? 'Отменить отказ' : 'Отменить выдачу')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Оплата старого долга: наличными и Kaspi (сначала — весь долг наличными); больше долга — предупреждение, остаток
/// авансом. Возвращает (наличные, Kaspi).
class _DebtDialog extends StatefulWidget {
  const _DebtDialog({required this.debt, required this.acceptKaspi});

  final int debt;
  final bool acceptKaspi;

  @override
  State<_DebtDialog> createState() => _DebtDialogState();
}

class _DebtDialogState extends State<_DebtDialog> {
  late final _cash = TextEditingController(text: widget.debt > 0 ? '${widget.debt}' : '');
  final _kaspi = TextEditingController();

  @override
  void dispose() {
    _cash.dispose();
    _kaspi.dispose();
    super.dispose();
  }

  int get _sum => (int.tryParse(_cash.text) ?? 0) + (widget.acceptKaspi ? int.tryParse(_kaspi.text) ?? 0 : 0);

  Widget _field(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
        decoration: InputDecoration(labelText: label, suffixText: '₸', hintText: '0'),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final sum = _sum, debt = widget.debt;
    final String? note = sum == 0
        ? null
        : sum > debt
            ? 'Больше долга на ${money(sum - debt.clamp(0, sum))} — останется у магазина авансом'
            : 'Останется долг ${money(debt - sum)}';
    return AlertDialog(
      title: const Text('Оплата долга'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(debt > 0 ? 'Долг ${money(debt)}' : 'Долга нет', style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 8),
            _field(_cash, 'Наличными'),
            if (widget.acceptKaspi) ...[
              const SizedBox(height: 8),
              _field(_kaspi, 'Kaspi'),
            ],
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(note, style: TextStyle(color: sum > debt ? AppColors.crimson : AppColors.inkSoft)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Назад')),
        TextButton(
          onPressed: sum == 0
              ? null
              : () => Navigator.pop(
                  context, (int.tryParse(_cash.text) ?? 0, widget.acceptKaspi ? int.tryParse(_kaspi.text) ?? 0 : 0)),
          child: Text(sum == 0 ? 'Принять' : 'Принять ${money(sum)}'),
        ),
      ],
    );
  }
}

/// Причина отказа: частая — одним касанием, или своя.
class _RefuseDialog extends StatefulWidget {
  const _RefuseDialog();

  @override
  State<_RefuseDialog> createState() => _RefuseDialogState();
}

class _RefuseDialogState extends State<_RefuseDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Магазин отказался'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final r in DeliveryBook.reasons)
                    ActionChip(label: Text(r), onPressed: () => setState(() => _c.text = r)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _c,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Причина'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Назад')),
          TextButton(
            onPressed: _c.text.trim().isEmpty ? null : () => Navigator.pop(context, _c.text.trim()),
            child: const Text('Отказ'),
          ),
        ],
      );
}
