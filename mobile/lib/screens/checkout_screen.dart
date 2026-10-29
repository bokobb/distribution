import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../data/order.dart';
import '../format.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/layout.dart';
import '../widgets/message_box.dart';
import '../widgets/shelf_photo.dart';

/// «Оформление» по макету AgentCheckout: заказ, возврат и к оплате; день доставки (тогда же экспедитор заберёт
/// возврат) — «Изменить»; оплата при доставке — что разрешено в настройках; у своего магазина — предупреждение о
/// лимите долга (заказ уйдёт руководителю) или о просрочке; фото полки, если обязательно; комментарий складу и
/// экспедитору. «Отправить» заканчивает визит заказом — без сети он уйдёт сам. Отправили — возвращает true.
/// С [editing] — правка уже взятого заказа: его оплата, день и комментарий, «Сохранить изменения» (отправленный
/// заказ меняется на сервере сразу — нужна сеть), фото полки не нужно.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen(
      {super.key,
      required this.outlet,
      required this.data,
      required this.visits,
      required this.items,
      required this.returns,
      required this.total,
      required this.returnTotal,
      this.editing});

  final Outlet outlet;
  final AgentData data;
  final VisitBook visits;
  final Map<int, int> items;
  final List<ReturnItem> returns;

  /// Заказ и возврат по ценам на телефоне, ₸.
  final int total;
  final int returnTotal;
  final Order? editing;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late String _payment = _payments.contains(widget.editing?.payment) ? widget.editing!.payment : 'CASH';
  late DateTime _delivery = switch (widget.editing) {
    // прошедший день доставки при правке — сегодня
    final e? => e.deliveryDate.isBefore(_today()) ? _today() : e.deliveryDate,
    null => _today().add(Duration(days: widget.data.settings.deliveryDays)),
  };
  late final _comment = TextEditingController(text: widget.editing?.comment);
  bool _busy = false;

  /// Доставка — не дальше двух недель от дня заказа (при правке — от дня, когда его взяли).
  DateTime get _lastDay {
    final from = widget.editing?.createdAt ?? _today();
    final last = DateTime(from.year, from.month, from.day).add(const Duration(days: 14));
    return last.isBefore(_delivery) ? _delivery : last;
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  int get _toPay => widget.total - widget.returnTotal;

  /// В долг — если разрешено и магазин не новый (первый заказ нового — без долга).
  List<String> get _payments => [
        'CASH',
        if (widget.data.settings.acceptKaspi) 'KASPI',
        if (widget.data.settings.allowCredit && !widget.outlet.pending) 'CREDIT',
      ];

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _delivery,
      firstDate: _today(),
      lastDate: _lastDay,
      helpText: 'Дата доставки',
    );
    if (d != null) setState(() => _delivery = d);
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final problem = widget.editing != null
          ? await widget.visits.editOrder(widget.editing!,
              items: widget.items,
              total: widget.total,
              returns: widget.returns,
              returnTotal: widget.returnTotal,
              payment: _payment,
              deliveryDate: _delivery,
              comment: _comment.text)
          : await widget.visits.finishWithOrder(
        items: widget.items,
        total: widget.total,
        returns: widget.returns,
        returnTotal: widget.returnTotal,
        payment: _payment,
        deliveryDate: _delivery,
        comment: _comment.text,
        settings: widget.data.settings,
      );
      if (!mounted) return;
      if (problem != null) return _say(problem);
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// У своего магазина: в долг сверх лимита — красное, иначе просрочка — янтарное. У чужого долгов не видно.
  Widget? _note() {
    final o = widget.outlet;
    if (!o.mine) return null;
    final after = o.debt + _toPay;
    if (_payment == 'CREDIT' && o.creditLimit > 0 && after > o.creditLimit) {
      return MessageBox.error(
        widget.data.settings.approvalOverLimit
            ? 'Заказ уйдёт руководителю на подтверждение. Предупредите магазин.'
            : 'Это больше лимита магазина — предупредите магазин.',
        title: 'Долг станет ${money(after)} при лимите ${money(o.creditLimit)}',
        stacked: true,
      );
    }
    if (o.overdue > 0) {
      return MessageBox.warn('Напомните магазину: экспедитор может принять её вместе с оплатой заказа.',
          title: 'Есть просрочка ${money(o.overdue)}', icon: Icons.schedule, stacked: true);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.outlet;
    final text = Theme.of(context).textTheme;
    final pieces = widget.items.values.fold(0, (a, b) => a + b);
    final backPieces = widget.returns.fold(0, (a, r) => a + r.qty);
    final note = _note();
    final payments = _payments;
    final withReturn = widget.returns.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.editing == null ? 'Оформление' : 'Изменение заказа'),
            Text([o.name, ?(o.address ?? o.landmark)].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text2)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  _sumRow('Заказ',
                      '${plural(widget.items.length, 'позиция', 'позиции', 'позиций')}, $pieces шт', money(widget.total)),
                  if (withReturn) ...[
                    const SizedBox(height: 8),
                    _sumRow('Возврат', '${plural(widget.returns.length, 'позиция', 'позиции', 'позиций')}, $backPieces шт',
                        '−${money(widget.returnTotal)}',
                        color: AppColors.warn),
                  ],
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Expanded(child: Text('К оплате', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                      Text(money(_toPay), style: text.headlineMedium!.copyWith(fontSize: 26, fontFeatures: tabular)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration:
                      const BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.all(Radius.circular(12))),
                  child: const Icon(Icons.local_shipping_outlined, size: 22, color: AppColors.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(withReturn ? 'Доставка и сбор возврата' : 'Доставка',
                          style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                      Text(dayTitle(_delivery), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _pickDate,
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.fill,
                    foregroundColor: AppColors.text,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Изменить'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('Оплата при доставке',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.label)),
          ),
          PillTabs(
            labels: [for (final p in payments) Order.paymentLabels[p]!],
            index: payments.indexOf(_payment),
            onChanged: (i) => setState(() => _payment = payments[i]),
          ),
          if (note != null) ...[const SizedBox(height: 12), note],
          if (widget.data.settings.shelfPhotoRequired && widget.editing == null) ...[
            const SizedBox(height: 12),
            ShelfPhotoButton(visits: widget.visits, required: true),
          ],
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text('Комментарий для склада и экспедитора',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.label)),
          ),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Например: привезти до 12:00, вход со двора', counterText: ''),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_queue, size: 16, color: AppColors.text2),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                          switch (widget.editing) {
                            null => 'Без сети заказ сохранится и уйдёт сам',
                            final e when e.sent => 'Заказ уже на сервере — изменение уйдёт сразу, нужна сеть',
                            _ => 'Заказ ещё не отправлен — уйдёт уже изменённым',
                          },
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: _busy ? null : _send,
                  child: Text(widget.editing != null
                      ? 'Сохранить изменения'
                      : withReturn
                          ? 'Отправить заказ и возврат'
                          : 'Отправить заказ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sumRow(String title, String note, String value, {Color? color}) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: title),
              TextSpan(text: ' · $note', style: const TextStyle(color: AppColors.text2)),
            ]), style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color, fontFeatures: tabular)),
        ],
      );
}
