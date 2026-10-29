import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/agent_data.dart';
import '../data/outlet_card.dart';
import '../format.dart';
import '../geo.dart';
import '../launch.dart';
import '../location.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/layout.dart';
import '../workday.dart';
import 'shop_facts.dart';
import 'visit_start.dart';

/// Карточка магазина по макету AgentOutlet: кто и где, сколько до него, прайс, с какого времени в базе; «Создать
/// заказ» и «Без заказа»; у своего магазина — долг с лимитом, просрочкой и последней оплатой (на день
/// синхронизации); что магазин берёт и история визитов — с сервера при открытии (нет сети — скажет). Позвонить —
/// если телефон известен (у своих). Заказ отправлен или визит закончен — карточка закрывается с true.
class OutletScreen extends StatefulWidget {
  const OutletScreen({super.key, required this.outlet, required this.data, required this.visits, required this.workday});

  final Outlet outlet;
  final AgentData data;
  final VisitBook visits;
  final Workday workday;

  @override
  State<OutletScreen> createState() => _OutletScreenState();
}

class _OutletScreenState extends State<OutletScreen> {
  OutletCard? _card;
  String? _error;
  bool _loading = false;
  Fix? _fix;

  /// Новый магазин ещё не на сервере — карточки там нет.
  bool get _local => widget.outlet.id < 0;

  @override
  void initState() {
    super.initState();
    _fix = widget.workday.lastPlace;
    _locate();
    if (!_local) _load();
  }

  Future<void> _locate() async {
    final f = await widget.visits.location.current();
    if (mounted && f != null) setState(() => _fix = f);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final card = OutletCard.fromJson(await widget.visits.outbox.api.outletCard(widget.outlet.id));
      if (mounted) setState(() => _card = card);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open({bool noOrder = false}) async {
    final done = await openVisit(context,
        data: widget.data, visits: widget.visits, workday: widget.workday, outlet: widget.outlet, noOrder: noOrder);
    if (done && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.outlet;
    final facts = ShopFacts(data: widget.data, visits: widget.visits, fix: _fix);
    final m = facts.meters(o);
    final since = _card?.createdOn ?? widget.data.stats[o.id]?.createdOn;
    final who = [o.legal, o.owner, o.address ?? o.landmark].nonNulls.join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Магазин'),
        actions: [
          if (o.phone != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Позвонить в магазин',
                style: IconButton.styleFrom(backgroundColor: AppColors.card),
                onPressed: () => call(context, o.phone!),
                icon: const Icon(Icons.call_outlined),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Text(o.name, style: Theme.of(context).textTheme.headlineMedium!.copyWith(fontSize: 24, height: 30 / 24)),
          if (who.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(who, style: const TextStyle(fontSize: 14, color: AppColors.text2)),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (m != null) Tag.brand(facts.here(o) ? 'Вы у магазина' : '${distanceLabel(m)} от вас'),
            Tag(o.priceLabel),
            if (o.pending) const Tag.brand('На проверке'),
            if (since != null) Tag('В базе с ${monthsOf[since.month - 1]} ${since.year}'),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              flex: 16,
              child: FilledButton.icon(
                onPressed: _open,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Создать заказ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 10,
              child: TextButton(
                onPressed: () => _open(noOrder: true),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.fill,
                  foregroundColor: AppColors.text,
                  minimumSize: const Size.fromHeight(50),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                  textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
                ),
                child: const Text('Без заказа'),
              ),
            ),
          ]),
          if (o.mine && !o.pending) ...[const SizedBox(height: 16), _debt(o)],
          if (o.pending) ...[
            const SizedBox(height: 16),
            const _Section(
              title: 'Новый магазин',
              children: [
                Text('Руководитель проверит магазин. До проверки заказ — без долга: наличные или Kaspi при доставке.',
                    style: TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.text2)),
              ],
            ),
          ],
          if (!_local) ...[
            const SizedBox(height: 16),
            if (_card case final card?) ...[
              _habits(card),
              const SizedBox(height: 16),
              _history(card),
            ] else
              _loadingOrError(),
          ],
        ],
      ),
    );
  }

  Widget _debt(Outlet o) {
    final limit = o.creditLimit;
    final share = limit > 0 ? (o.debt / limit).clamp(0.0, 1.0) : null;
    final barColor = o.overLimit ? AppColors.err : o.overdue > 0 ? const Color(0xFFE39B2D) : AppColors.accent;
    return _Section(
      title: 'Долг магазина',
      noteBelow: true,
      note: [limit > 0 ? 'лимит ${money(limit)}' : 'без лимита', 'отсрочка ${plural(o.paymentDays, 'день', 'дня', 'дней')}']
          .join(' · '),
      children: [
        Text(o.debt > 0 ? money(o.debt) : 'Долга нет',
            style: TextStyle(
                fontSize: 26,
                height: 32 / 26,
                fontWeight: FontWeight.w700,
                color: o.overLimit ? AppColors.err : AppColors.text,
                fontFeatures: tabular)),
        if (share != null && o.debt > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: share, minHeight: 6, color: barColor, backgroundColor: AppColors.fill),
          ),
        ],
        if (o.overdue > 0 || o.lastPaymentDate != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (o.overdue > 0)
              Text('Просрочено ${money(o.overdue)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF8A5000))),
            const Spacer(),
            if (o.lastPaymentDate != null)
              Text('оплата ${dayMon(o.lastPaymentDate!)} — ${money(o.lastPaymentSum)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
          ]),
        ],
        const SizedBox(height: 6),
        Text('На ${date(widget.data.date)}', style: const TextStyle(fontSize: 12, color: AppColors.icon)),
      ],
    );
  }

  Widget _habits(OutletCard c) {
    final share = c.returnShare;
    final reason = c.returnReason == null ? null : _reasonWord[c.returnReason];
    final since = c.stoppedSince;
    final weeks = since == null ? 0 : (DateUtils.dateOnly(DateTime.now()).difference(since).inDays / 7).floor();
    return _Section(
      title: 'Что берёт магазин',
      children: [
        _line('Средний заказ', c.avgOrder > 0 ? '${money(c.avgOrder)} · ${c.frequency}' : 'заказов за 90 дней не было'),
        if (share != null)
          _line('Возвраты',
              c.returned == 0 ? 'не было' : ['$share% от заказов', if (reason != null) 'в основном $reason'].join(' · ')),
        if (c.stopped != null)
          _line('Перестал брать', [c.stopped!, if (weeks > 0) plural(weeks, 'неделя', 'недели', 'недель')].join(' · '),
              alarm: true),
      ],
    );
  }

  static const _reasonWord = {'EXPIRED': 'срок годности', 'DEFECT': 'брак', 'PACKAGING': 'упаковка'};

  /// Подпись сверху, значение под ней — длинное не рвётся по краю.
  Widget _line(String label, String value, {bool alarm = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (alarm)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(color: AppColors.err, shape: BoxShape.circle),
              ),
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text2)),
          ]),
          const SizedBox(height: 1),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ]),
      );

  Widget _history(OutletCard c) => _Section(
        title: 'История визитов',
        note: 'заказы и возвраты',
        children: [
          if (c.history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('За 90 дней визитов не было', style: TextStyle(fontSize: 14, color: AppColors.text2)),
            ),
          for (final (i, h) in c.history.indexed) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h.order ? '${dayMon(h.at)} · заказ ${money(h.orderTotal)}' : '${dayMon(h.at)} · без заказа',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    Text(
                        h.order
                            ? h.returnTotal > 0
                                ? ['возврат ${money(h.returnTotal)}', ?h.returnReasonText].join(' · ')
                                : 'без возврата'
                            : (h.reason ?? 'причина не указана').toLowerCase(),
                        style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
                  ]),
                ),
                if (h.statusLabel != null) ...[const SizedBox(width: 8), _status(h)],
              ]),
            ),
          ],
        ],
      );

  static Widget _status(HistoryItem h) => switch (h.status) {
        'DELIVERED' => Tag.ok(h.statusLabel!),
        'PARTIAL' => Tag.warn(h.statusLabel!),
        'CANCELLED' || 'REFUSED' => Tag.err(h.statusLabel!),
        'NEEDS_APPROVAL' => Tag.brand(h.statusLabel!),
        _ => Tag(h.statusLabel!),
      };

  Widget _loadingOrError() => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(16))),
        child: _loading || _error == null
            ? const Row(children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Загружаю, что берёт магазин…', style: TextStyle(color: AppColors.text2)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_error. Что берёт магазин и историю визитов покажем, когда будет связь.',
                    style: const TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.text2)),
                const SizedBox(height: 8),
                TextButton(onPressed: _load, child: const Text('Повторить')),
              ]),
      );
}

/// Белый блок с заголовком и пояснением справа.
class _Section extends StatelessWidget {
  const _Section({required this.title, this.note, this.noteBelow = false, required this.children});

  final String title;
  final String? note;

  /// Пояснение длинное — под заголовком, а не справа.
  final bool noteBelow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: const BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.all(Radius.circular(16))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (noteBelow) ...[
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (note != null)
              Text(note!, style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              if (note != null)
                Expanded(
                  child: Text(note!,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
                ),
            ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      );
}
