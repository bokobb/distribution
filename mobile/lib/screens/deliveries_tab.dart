import 'package:flutter/material.dart';

import '../data/expeditor_data.dart';
import '../day_summary.dart';
import '../deliveries.dart';
import '../format.dart';
import '../geo.dart';
import '../launch.dart';
import '../theme.dart';
import '../widgets/layout.dart';
import '../widgets/workday_card.dart';
import '../workday.dart';
import 'goods_screen.dart';
import 'home_parts.dart';
import 'proof_screen.dart';
import 'route_map_screen.dart';
import 'stop_screen.dart';

/// «Доставки» — главный экран экспедитора по макету ExpTrip: сколько доставлено и сколько наличных на руках, вкладки
/// «Новые» и «Доставлены». В «Новых» раскрыта одна точка (сначала — следующая по маршруту): звонок, «Поехали» (карты
/// на телефоне), «Состав» (выдать не всё, забрать негодное), сколько к оплате и сколько передал магазин, «Принять
/// старый долг» и «Доставлено». Остальные — свёрнуты, нажать — раскрыть. «Доставлены» — что выдано, с деньгами;
/// нажать — карточка точки (отменить, накладная). Рейс на завтра — внизу «Новых», посмотреть заранее.
class DeliveriesTab extends StatefulWidget {
  const DeliveriesTab(
      {super.key,
      required this.data,
      required this.loading,
      this.syncError,
      required this.onRefresh,
      required this.deliveries,
      required this.workday,
      required this.expeditor,
      required this.onCash});

  final ExpeditorData? data;
  final bool loading;
  final String? syncError;
  final Future<void> Function() onRefresh;
  final DeliveryBook deliveries;
  final Workday workday;

  /// Кто везёт — для накладной.
  final String expeditor;

  /// «Перейти к сдаче кассы».
  final VoidCallback onCash;

  @override
  State<DeliveriesTab> createState() => _DeliveriesTabState();
}

class _DeliveriesTabState extends State<DeliveriesTab> {
  bool _doneTab = false;

  /// Раскрытая точка — id заказа; null — следующая по маршруту.
  int? _open;
  final _cash = <int, TextEditingController>{};
  final _debt = <int, TextEditingController>{};
  final _debtOpen = <int>{};

  /// Выдаётся не всё: заказ → товар → штук (из «Состава»).
  final _plan = <int, Map<int, int>>{};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._cash.values, ..._debt.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _cashOf(int orderId) => _cash.putIfAbsent(orderId, TextEditingController.new);
  TextEditingController _debtOf(int orderId) => _debt.putIfAbsent(orderId, TextEditingController.new);
  static int _value(TextEditingController c) => int.tryParse(c.text) ?? 0;

  void _say(String text, {bool done = false}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Row(children: [
      if (done) ...[const Icon(Icons.check, color: Color(0xFF5BD69B), size: 18), const SizedBox(width: 10)],
      Expanded(child: Text(text)),
    ])));

  /// На сколько выдаётся товара: по заказу или как поправили в «Составе».
  int _goods(Stop s) {
    final plan = _plan[s.order.id];
    if (plan == null) return s.order.total;
    return s.order.lines.fold(0, (a, l) => a + (plan[l.productId] ?? 0) * l.price);
  }

  /// Негодный товар, принятый у магазина сегодня: уменьшает, сколько он платит.
  int _returns(Stop s) =>
      widget.deliveries.returnsAt(s.outlet.id).where((r) => r.error == null).fold(0, (a, r) => a + r.total);

  int _toPay(Stop s) => (_goods(s) - _returns(s) - s.order.paid).clamp(0, 1 << 40);

  String? _distance(Stop s) {
    final me = widget.workday.lastPlace, o = s.outlet;
    if (me == null || o.lat == null || o.lng == null) return null;
    return distanceLabel(metersBetween(me.lat, me.lng, o.lat!, o.lng!));
  }

  Future<void> _openGoods(TripInfo t, Stop s) async {
    final data = widget.data!;
    final plan = await Navigator.push<Map<int, int>>(
        context,
        MaterialPageRoute(
            builder: (_) => GoodsScreen(
                stop: s,
                trip: t,
                data: data,
                deliveries: widget.deliveries,
                workday: widget.workday,
                expeditor: widget.expeditor,
                plan: _plan[s.order.id])));
    if (plan == null || !mounted) return;
    setState(() {
      final all = s.order.lines.every((l) => plan[l.productId] == l.qty);
      if (all) {
        _plan.remove(s.order.id);
      } else {
        _plan[s.order.id] = plan;
      }
    });
  }

  Future<void> _deliver(TripInfo t, Stop s) async {
    if (!widget.workday.open) return _say(startDayFirst);
    final order = s.order, id = order.id;
    final toPay = _toPay(s);
    final credit = order.payment == 'CREDIT';
    final cashField = _cashOf(id);
    if (!credit && cashField.text.isEmpty && toPay > 0) return _say('Введите сумму, которую передал магазин');
    final paid = credit ? 0 : _value(cashField);
    if (paid > toPay) return _say('Получено больше, чем к оплате, на ${money(paid - toPay)}');
    final debt = _debtOpen.contains(id) ? _value(_debtOf(id)) : 0;
    final items = _plan[id] ?? {for (final l in order.lines) l.productId: l.qty};
    final kaspi = order.payment == 'KASPI';
    final proof = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => ProofScreen(
                stop: s, camera: widget.deliveries.camera, forOrder: credit ? null : paid, oldDebt: debt)));
    if (proof == null || !mounted) return;
    setState(() => _busy = true);
    var problem = await widget.deliveries.deliver(t, s,
        items: items, cash: kaspi ? 0 : paid, kaspi: kaspi ? paid : 0, proof: proof, settings: widget.data!.settings);
    if (problem == null && debt > 0) {
      problem = await widget.deliveries.payDebt(t, s, cash: debt, settings: widget.data!.settings);
      if (problem != null) problem = 'Выдача сохранена, а старый долг — нет: $problem';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (problem == null || problem.startsWith('Выдача сохранена')) {
        _cash.remove(id)?.dispose();
        _debt.remove(id)?.dispose();
        _debtOpen.remove(id);
        _plan.remove(id);
        _open = null;
      }
    });
    if (problem == null) {
      _say('${s.outlet.name} — доставлено', done: true);
    } else {
      _say(problem);
    }
  }

  Future<void> _refuse(TripInfo t, Stop s) async {
    if (!widget.workday.open) return _say(startDayFirst);
    final reason = await showDialog<String>(context: context, builder: (_) => const RefuseDialog());
    if (reason == null || !mounted) return;
    final problem = await widget.deliveries.refuse(t, s, reason);
    if (!mounted) return;
    if (problem == null) setState(() => _open = null);
    _say(problem ?? '${s.outlet.name} — отказ сохранён');
  }

  void _details(ExpeditorData data, TripInfo t, Stop s) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => StopScreen(
              stop: s,
              trip: t,
              data: data,
              deliveries: widget.deliveries,
              workday: widget.workday,
              expeditor: widget.expeditor)));

  void _map(ExpeditorData data) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => RouteMapScreen(
              data: data,
              deliveries: widget.deliveries,
              workday: widget.workday,
              onOpen: (s) => setState(() {
                    _doneTab = false;
                    _open = s.order.id;
                  }))));

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final vehicle = data?.current.firstOrNull?.vehicle ?? data?.upcoming.firstOrNull?.vehicle;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.deliveries, widget.workday]),
        builder: (context, _) {
          final current = [
            for (final t in data?.current ?? const <TripInfo>[])
              for (final s in t.stops) (t, s)
          ];
          final pending = [for (final p in current) if (!widget.deliveries.done(p.$2.order)) p];
          final done = [for (final p in current) if (widget.deliveries.done(p.$2.order)) p];
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              PageHeader(
                title: 'Доставки',
                subtitle: [dayTitle(DateTime.now()), ?vehicle?.replaceAll(' ', '\u00a0')].join(' · '), // номер машины не рвётся
                trailing: [
                  if (data != null && current.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () => _map(data),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.fromLTRB(14, 0, 16, 0),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.map_outlined, size: 20),
                      label: const Text('Маршрут'),
                    ),
                ],
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: WorkdayCard(workday: widget.workday)),
              _status(data),
              if (data == null && !widget.loading)
                const EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Нет данных',
                  text: 'Подключитесь к интернету и потяните экран вниз, чтобы получить рейс.',
                ),
              if (data != null && current.isEmpty)
                const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'Рейса на сегодня нет',
                  text: 'Когда вам отгрузят заказы, они появятся здесь. Потяните экран вниз, чтобы обновить.',
                ),
              if (data != null && current.isNotEmpty) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: _totals(data, current.length, done.length)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: PillTabs(
                    labels: ['Новые · ${pending.length}', 'Доставлены · ${done.length}'],
                    index: _doneTab ? 1 : 0,
                    onChanged: (i) => setState(() => _doneTab = i == 1),
                  ),
                ),
                if (_doneTab)
                  for (final (t, s) in done.reversed) _doneTile(data, t, s)
                else ...[
                  for (final (i, (t, s)) in pending.indexed)
                    (_open ?? pending.first.$2.order.id) == s.order.id
                        ? _openCard(data, t, s, next: i == 0)
                        : _closedTile(t, s),
                  if (pending.isEmpty) _allDone(),
                ],
              ],
              if (data != null && !_doneTab)
                for (final t in data.upcoming) ..._ahead(data, t),
            ],
          );
        },
      ),
    );
  }

  Widget _status(ExpeditorData? data) {
    final String text;
    final err = widget.syncError;
    if (widget.loading) {
      text = 'Обновляю…';
    } else if (err != null) {
      text = data == null ? err : '$err. Данные ${when(data.syncedAt)}';
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(err != null ? Icons.cloud_off_outlined : Icons.sync, size: 16, color: err != null ? AppColors.err : AppColors.text2),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: err != null ? AppColors.err : AppColors.text2)),
          ),
        ],
      ),
    );
  }

  /// «Доставлено 5 из 14» с полоской и «Наличные на руках».
  Widget _totals(ExpeditorData data, int total, int done) {
    var cash = 0, oldDebt = 0, cashStops = 0;
    for (final t in data.current) {
      final s = TripSummary.of(t, widget.deliveries, data.syncedAt);
      cash += s.cash;
      oldDebt += s.oldDebt;
      for (final st in t.stops) {
        final local = widget.deliveries.of(st.order.id);
        final paidCash = local != null && local.error == null
            ? local.cash > 0
            : st.order.done && st.order.payment == 'CASH' && st.order.paid > 0;
        if (paidCash) cashStops++;
      }
    }
    const small = TextStyle(fontSize: 13, height: 16 / 13, color: AppColors.text2);
    const big = TextStyle(fontSize: 20, height: 24 / 20, fontWeight: FontWeight.w700, fontFeatures: tabular);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Доставлено', style: small),
                    const SizedBox(height: 6),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '$done ', style: big),
                      TextSpan(
                          text: 'из $total',
                          style: big.copyWith(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text2)),
                    ])),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                      child: LinearProgressIndicator(
                          value: total == 0 ? 0 : done / total,
                          minHeight: 4,
                          backgroundColor: AppColors.line,
                          color: AppColors.accent),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Наличные на руках', style: small),
                    const SizedBox(height: 6),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(money(cash), style: big)),
                    const SizedBox(height: 4),
                    Text(
                        oldDebt > 0
                            ? 'вкл. долги ${money(oldDebt)}'
                            : cashStops > 0
                                ? 'за ${plural(cashStops, 'доставку', 'доставки', 'доставок')}'
                                : 'пока нет',
                        style: small.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _number(Stop s, {required bool strong}) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: strong ? AppColors.accent : AppColors.fill, shape: BoxShape.circle),
        child: Text('${s.position + 1}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: strong ? Colors.white : AppColors.text)),
      );

  Widget _payTag(Stop s) => s.order.payment == 'CREDIT' ? Tag.warn(s.order.paymentLabel) : Tag(s.order.paymentLabel);

  Widget _closedTile(TripInfo t, Stop s) {
    final place = s.outlet.address ?? s.outlet.landmark;
    final dist = _distance(s);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _open = s.order.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _number(s, strong: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.outlet.name, style: Theme.of(context).textTheme.titleMedium),
                      if (place != null)
                        Text(place,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text(money(_toPay(s)), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        _payTag(s),
                      ]),
                    ],
                  ),
                ),
                if (dist != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 8),
                    child: Text(dist, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text2)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _openCard(ExpeditorData data, TripInfo t, Stop s, {required bool next}) {
    final o = s.outlet, order = s.order, id = order.id;
    final dist = _distance(s);
    final place = [o.address ?? o.landmark, plural(order.lines.length, 'позиция', 'позиции', 'позиций')].nonNulls.join(' · ');
    final toPay = _toPay(s);
    final credit = order.payment == 'CREDIT';
    final hasPlace = o.lat != null && o.lng != null || o.address != null || o.landmark != null;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.all(Radius.circular(20)),
          boxShadow: [
            BoxShadow(color: AppColors.accent, spreadRadius: 1.5),
            BoxShadow(color: Color(0x804136F1), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -18),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              _number(s, strong: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    [next ? 'Следующая' : 'Точка ${s.position + 1}', ?dist, if (t.date.isBefore(data.date)) 'с ${date(t.date)}']
                        .join(' · '),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentPressed)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(o.name, style: text.titleLarge),
            Text(place, style: const TextStyle(fontSize: 14, color: AppColors.text2)),
            if (order.comment != null && order.comment!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Комментарий: ${order.comment}', style: const TextStyle(fontSize: 14, color: AppColors.label)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _action(Icons.call_outlined, 'Звонок', o.phone == null ? null : () => call(context, o.phone!))),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                    Icons.navigation_outlined,
                    'Поехали',
                    !hasPlace
                        ? null
                        : () => route(context, lat: o.lat, lng: o.lng, name: o.name, address: o.address ?? o.landmark)),
              ),
              const SizedBox(width: 8),
              Expanded(child: _action(Icons.inventory_2_outlined, 'Состав', () => _openGoods(t, s))),
            ]),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                      ['К оплате · ${order.paymentLabel}', if (_plan.containsKey(id)) 'выдаётся не всё'].join(' · '),
                      style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                ),
                Text(money(toPay), style: text.headlineSmall),
              ],
            ),
            const SizedBox(height: 12),
            if (credit)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: const BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.all(Radius.circular(12))),
                child: const Text('Оплата позже: сумма добавится к долгу магазина.',
                    style: TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.label)),
              )
            else
              _paidField(order, toPay),
            if (o.debt > 0) ...[const SizedBox(height: 12), _oldDebt(s, credit ? 0 : _value(_cashOf(id)))],
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: _busy || t.date.isAfter(data.date) ? null : () => _deliver(t, s),
              icon: const Icon(Icons.check),
              label: const Text('Доставлено'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _refuse(t, s),
              style: TextButton.styleFrom(foregroundColor: AppColors.err),
              child: const Text('Магазин отказался'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) => OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );

  Widget _paidField(TripOrder order, int toPay) {
    final c = _cashOf(order.id);
    final paid = _value(c);
    final diff = paid - toPay;
    final (String text, Color color) = c.text.isEmpty
        ? ('Введите сумму, которую передал магазин', AppColors.text2)
        : diff == 0
            ? ('Сумма совпадает с заказом', AppColors.ok)
            : diff < 0
                ? ('Не хватает ${money(-diff)} — останется долгом', AppColors.warn)
                : ('Больше суммы заказа на ${money(diff)}', AppColors.err);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(order.payment == 'KASPI' ? 'Получено на Kaspi' : 'Получено наличными',
            style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        MoneyInput(
          controller: c,
          semanticLabel: order.payment == 'KASPI' ? 'Получено на Kaspi' : 'Получено наличными',
          fillLabel: 'Вся сумма',
          onFill: () => setState(() => c.text = '$toPay'),
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (c.text.isNotEmpty) ...[
            Icon(diff == 0 ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: color),
            const SizedBox(width: 6),
          ],
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13, fontWeight: c.text.isEmpty ? FontWeight.w500 : FontWeight.w600, color: color))),
        ]),
      ],
    );
  }

  /// «Принять старый долг» — свёрнуто пунктиром; раскрыто — сумма «В счёт старого долга» и «Весь долг».
  Widget _oldDebt(Stop s, int paidForOrder) {
    final id = s.order.id, debt = s.outlet.debt;
    if (!_debtOpen.contains(id)) {
      return InkWell(
        onTap: () => setState(() => _debtOpen.add(id)),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Container(
          height: 48,
          padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            border: Border.all(color: const Color(0xFFD5D9E0), width: 1.5),
          ),
          child: Row(children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: AppColors.warnBg, shape: BoxShape.circle),
              child: const Icon(Icons.add, size: 16, color: Color(0xFF8A5000)),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Принять старый долг', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            Text(money(debt), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF8A5000))),
          ]),
        ),
      );
    }
    final c = _debtOf(id);
    final got = _value(c);
    final diff = got - debt;
    final (String text, Color color) = c.text.isEmpty
        ? ('Отдельно от оплаты заказа', AppColors.text2)
        : diff == 0
            ? ('Долг закрыт полностью', AppColors.ok)
            : diff < 0
                ? ('Останется долг ${money(-diff)}', AppColors.warn)
                : ('Больше долга на ${money(diff)} — уйдёт авансом', AppColors.err);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.all(Radius.circular(14))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('В счёт старого долга', style: Theme.of(context).textTheme.labelMedium)),
            Text('долг ${money(debt)}', style: const TextStyle(fontSize: 13, color: AppColors.text2)),
          ]),
          const SizedBox(height: 8),
          MoneyInput(
            controller: c,
            strong: false,
            semanticLabel: 'В счёт старого долга',
            fillLabel: 'Весь долг',
            onFill: () => setState(() => c.text = '$debt'),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
            if (got > 0)
              Text('всего ${money(paidForOrder + got)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ],
      ),
    );
  }

  Widget _allDone() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: AppColors.okBg, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: AppColors.ok, size: 28),
              ),
              const SizedBox(height: 8),
              const Text('Все доставки выполнены', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              TextButton(onPressed: widget.onCash, child: const Text('Перейти к сдаче кассы')),
            ]),
          ),
        ),
      );

  Widget _doneTile(ExpeditorData data, TripInfo t, Stop s) {
    final local = widget.deliveries.of(s.order.id);
    final order = s.order;
    final refused = local != null && local.error == null ? local.refused : order.refused;
    final partial = local != null && local.error == null ? local.partial : order.status == 'PARTIAL';
    final debtPaid = widget.deliveries.paymentsAt(s.outlet.id).where((p) => p.error == null).fold(0, (a, p) => a + p.amount);
    final String line;
    if (refused) {
      line = local?.refuseReason != null ? 'Отказ: ${local!.refuseReason}' : 'Отказ';
    } else if (local != null && local.error == null) {
      final base = local.cash > 0
          ? 'Наличные · ${money(local.cash)}'
          : local.kaspi > 0
              ? 'Kaspi · ${money(local.kaspi)}'
              : 'В долг · ${money(local.total)}';
      line = debtPaid > 0 ? '$base + долг ${money(debtPaid)}' : base;
    } else {
      line = '${order.paymentLabel} · ${money(order.paid > 0 ? order.paid : order.total)}';
    }
    final note = local == null
        ? null
        : local.error != null
            ? 'Сервер не принял: ${local.error}'
            : local.sent
                ? null
                : 'ждёт отправки';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _details(data, t, s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: refused ? AppColors.errBg : AppColors.okBg, shape: BoxShape.circle),
                  child: Icon(refused ? Icons.close : Icons.check, size: 16, color: refused ? AppColors.err : AppColors.ok),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.outlet.name, style: Theme.of(context).textTheme.titleMedium),
                      if ((s.outlet.address ?? s.outlet.landmark) != null)
                        Text((s.outlet.address ?? s.outlet.landmark)!,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(line, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        if (partial && !refused) const Tag.warn('Частично'),
                      ]),
                      if (note != null)
                        Text(note,
                            style: TextStyle(fontSize: 13, color: local!.error != null ? AppColors.err : AppColors.text2)),
                    ],
                  ),
                ),
                if (local != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 8),
                    child: Text(time(local.deliveredAt),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text2)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _ahead(ExpeditorData data, TripInfo t) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
          child: Text(
              ['На ${date(t.date)}', t.number, plural(t.stops.length, 'точка', 'точки', 'точек')].join(' · '),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)),
        ),
        for (final s in t.stops)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: _number(s, strong: false),
                title: Text(s.outlet.name),
                subtitle: Text('${money(s.order.total)} · ${s.order.paymentLabel}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _details(data, t, s),
              ),
            ),
          ),
      ];
}
