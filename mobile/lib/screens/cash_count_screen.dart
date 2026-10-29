import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../theme.dart';

/// «Сдача кассы» по макету ExpCashCount: экспедитор пересчитывает наличные по купюрам и монетам и сверяет с тем,
/// что нужно сдать; Kaspi уже на счёте. Счёт только на телефоне — приём подтверждает оператор в кассе админки.
class CashCountScreen extends StatefulWidget {
  const CashCountScreen({super.key, required this.expected, required this.kaspi, required this.payments});

  /// Наличные на руках по данным рейса.
  final int expected;
  final int kaspi;

  /// Сколько оплат наличными за день.
  final int payments;

  /// Купюры тенге, что ходят у магазинов.
  static const notes = [20000, 10000, 5000, 2000, 1000, 500];

  @override
  State<CashCountScreen> createState() => _CashCountScreenState();
}

class _CashCountScreenState extends State<CashCountScreen> {
  final _count = <int, TextEditingController>{
    for (final n in CashCountScreen.notes) n: TextEditingController(),
  };
  final _coins = TextEditingController();

  @override
  void dispose() {
    for (final c in [..._count.values, _coins]) {
      c.dispose();
    }
    super.dispose();
  }

  int _of(int note) => int.tryParse(_count[note]!.text) ?? 0;
  int get _coinsSum => int.tryParse(_coins.text) ?? 0;
  int get _notesQty => CashCountScreen.notes.fold(0, (a, n) => a + _of(n));
  int get _counted => CashCountScreen.notes.fold(0, (a, n) => a + _of(n) * n) + _coinsSum;

  void _set(int note, int n) => setState(() => _count[note]!.text = n <= 0 ? '' : '${n.clamp(0, 999)}');

  void _reset() => setState(() {
        for (final c in _count.values) {
          c.clear();
        }
        _coins.clear();
      });

  Future<void> _submit() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Передайте ${money(_counted)}'),
        content: const Text('Оператор пересчитает наличные и подтвердит приём в кассе — после этого рейс закроется.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Понятно'))],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final counted = _counted, diff = counted - widget.expected;
    final (String status, Color bg, Color fg, IconData icon) = diff == 0
        ? ('Сходится с суммой к сдаче', AppColors.okBg, const Color(0xFF0B5A40), Icons.check_circle_outline)
        : diff < 0
            ? ('Не хватает ${money(-diff)} — пересчитайте', AppColors.warnBg, const Color(0xFF8A5000), Icons.error_outline)
            : ('Лишние ${money(diff)} — проверьте купюры', AppColors.errBg, const Color(0xFFA3241A), Icons.error_outline);
    final qty = _notesQty;
    const small = TextStyle(fontSize: 12, color: AppColors.text2);
    const big = TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700, fontFeatures: tabular);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сдача кассы'),
            Text('Пересчитайте наличные по купюрам',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text2)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('Нужно сдать', style: TextStyle(fontSize: 13, color: AppColors.text2)),
                                FittedBox(fit: BoxFit.scaleDown, child: Text(money(widget.expected), style: big)),
                                Text('наличные за ${plural(widget.payments, 'оплату', 'оплаты', 'оплат')}', style: small),
                              ]),
                            ),
                            const VerticalDivider(width: 32),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('Посчитано', style: TextStyle(fontSize: 13, color: AppColors.text2)),
                                FittedBox(fit: BoxFit.scaleDown, child: Text(money(counted), style: big)),
                                Text(
                                    '${plural(qty, 'купюра', 'купюры', 'купюр')}${_coinsSum > 0 ? ' и монеты' : ''}',
                                    style: small),
                              ]),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 40),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(10))),
                            child: Row(children: [
                              Icon(icon, size: 18, color: fg),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(status,
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg, fontFeatures: tabular))),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                        child: Row(children: [
                          const Expanded(
                              child: Text('Купюры и монеты', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                          TextButton(
                            onPressed: _reset,
                            style: TextButton.styleFrom(foregroundColor: AppColors.accent, minimumSize: const Size(0, 36)),
                            child: const Text('Сбросить'),
                          ),
                        ]),
                      ),
                      for (final n in CashCountScreen.notes) _noteRow(n),
                      _coinsRow(),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
                if (widget.kaspi > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Row(children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.icon),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Kaspi ${money(widget.kaspi)} уже на счёте — его сдавать не нужно',
                            style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFeatures: tabular)),
                      ),
                    ]),
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
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                      diff == 0
                          ? 'Оператор пересчитает и подтвердит приём'
                          : 'Расхождение ${money(diff.abs())} попадёт в акт приёма',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.text, minimumSize: const Size.fromHeight(54)),
                    onPressed: counted == 0 ? null : _submit,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text('Сдать ${money(counted)}'),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, {double radius = 6}) => Container(
        width: 74,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFF7F8FA), Color(0xFFEEF0F3)]),
          border: Border.all(color: const Color(0xFFDADDE3)),
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: tabular)),
      );

  Widget _sum(int v) => SizedBox(
        width: 92,
        child: Text(v > 0 ? money(v) : '—',
            textAlign: TextAlign.end,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: v > 0 ? AppColors.text : const Color(0xFFB4B9C2),
                fontFeatures: tabular)),
      );

  Widget _noteRow(int note) {
    final n = _of(note);
    final label = amount(note);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
      child: Row(children: [
        _chip(label),
        Expanded(
          child: Center(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.field),
                borderRadius: const BorderRadius.all(Radius.circular(12)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 38,
                  child: IconButton(
                      tooltip: 'Убрать купюру $label',
                      padding: EdgeInsets.zero,
                      onPressed: n == 0 ? null : () => _set(note, n - 1),
                      icon: const Icon(Icons.remove, size: 18)),
                ),
                Container(
                  width: 44,
                  decoration: const BoxDecoration(
                      border: Border.symmetric(vertical: BorderSide(color: AppColors.divider))),
                  child: Semantics(
                    label: 'Купюр по $label',
                    child: TextField(
                      controller: _count[note],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: tabular),
                      decoration: const InputDecoration(
                        hintText: '0',
                        isDense: true,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 9),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: IconButton(
                      tooltip: 'Добавить купюру $label',
                      padding: EdgeInsets.zero,
                      onPressed: n >= 999 ? null : () => _set(note, n + 1),
                      icon: const Icon(Icons.add, size: 18)),
                ),
              ]),
            ),
          ),
        ),
        _sum(n * note),
      ]),
    );
  }

  Widget _coinsRow() => Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
        child: Row(children: [
          _chip('Монеты', radius: 16),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 122,
                height: 40,
                child: TextField(
                  controller: _coins,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.end,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: tabular),
                  decoration: const InputDecoration(
                    hintText: '0',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    suffixText: '₸',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: AppColors.field)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: AppColors.field)),
                  ),
                ),
              ),
            ),
          ),
          _sum(_coinsSum),
        ]),
      );
}
