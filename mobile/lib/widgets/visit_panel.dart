import 'dart:io';

import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../data/visit.dart';
import '../format.dart';
import '../geo.dart';
import '../theme.dart';
import '../visits.dart';
import '../workday.dart';

/// Визит в карточке магазина: «Начать визит» (рабочий день открыт, агент рядом с магазином), пока идёт — фото
/// полки, «Без заказа» с причиной, «Отменить»; после — когда был и с каким итогом.
class VisitPanel extends StatefulWidget {
  const VisitPanel(
      {super.key, required this.outlet, required this.data, this.routeId, required this.visits, required this.workday});

  final Outlet outlet;
  final AgentData data;
  final int? routeId;
  final VisitBook visits;
  final Workday workday;

  @override
  State<VisitPanel> createState() => _VisitPanelState();
}

class _VisitPanelState extends State<VisitPanel> {
  bool _busy = false;

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _busy = true);
    try {
      final problem = await action();
      if (problem != null && mounted) _say(problem);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (!widget.workday.open) {
      _say('Сначала начните рабочий день на главном экране');
      return;
    }
    await _run(() => widget.visits.start(widget.outlet, routeId: widget.routeId, radius: widget.data.settings.visitRadius));
  }

  Future<void> _noOrder() async {
    final s = widget.data.settings;
    if (s.shelfPhotoRequired && widget.visits.current?.photo == null) {
      _say('Сначала сфотографируйте полку');
      return;
    }
    final reason = await _askReason(context, required: s.refuseReasonRequired);
    if (reason == null) return;
    await _run(() => widget.visits.finishNoOrder(reason, s));
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Отменить визит?'),
        content: const Text('Визит и фото будут стёрты, на сервер они не уйдут.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Отменить визит')),
        ],
      ),
    );
    if (ok == true) await widget.visits.cancel();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([widget.visits, widget.workday]),
        builder: (context, _) {
          final current = widget.visits.current;
          if (current != null && current.outletId == widget.outlet.id) return _going(current);
          final last = widget.visits.lastAt(widget.outlet.id);
          final elsewhere = current == null ? null : widget.data.outlets[current.outletId]?.name ?? 'другой магазин';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (last != null) ...[
                    Text('Сегодня был в ${time(last.startedAt)} — ${visitResult(last)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (visitNote(last) case final note?)
                      Text(note.$1, style: TextStyle(color: note.$2 ? AppColors.crimson : AppColors.inkSoft)),
                    const SizedBox(height: 12),
                  ],
                  if (elsewhere != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Идёт визит в «$elsewhere» — сначала закончите его',
                          style: const TextStyle(color: AppColors.crimson)),
                    ),
                  FilledButton.icon(
                    onPressed: _busy || elsewhere != null ? null : _start,
                    icon: _busy ? const _Spinner() : const Icon(Icons.storefront_outlined),
                    label: Text(_busy ? 'Определяю, где вы…' : last == null ? 'Начать визит' : 'Начать визит ещё раз'),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _going(Visit v) {
    final s = widget.data.settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.radio_button_checked, size: 18, color: AppColors.ok),
                const SizedBox(width: 8),
                Text('Визит с ${time(v.startedAt)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                  v.distance == null
                      ? 'У магазина нет точки на карте — визит отмечен там, где вы'
                      : '${distanceLabel(v.distance!)} от магазина',
                  style: const TextStyle(color: AppColors.inkSoft)),
            ),
            const SizedBox(height: 12),
            if (v.photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(v.photo!), height: 160, fit: BoxFit.cover),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(widget.visits.takePhoto),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(v.photo == null ? (s.shelfPhotoRequired ? 'Фото полки (обязательно)' : 'Фото полки') : 'Переснять'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _noOrder, child: const Text('Без заказа')),
            TextButton(onPressed: _busy ? null : _cancel, child: const Text('Отменить визит')),
          ],
        ),
      ),
    );
  }
}

/// «с заказом», «без заказа: Нет денег», «идёт».
String visitResult(Visit v) => v.open
    ? 'визит идёт'
    : v.result == 'ORDER'
        ? 'с заказом'
        : v.reason == null
            ? 'без заказа'
            : 'без заказа: ${v.reason}';

/// Отправлен ли визит; второе — тревожно (сервер не принял).
(String, bool)? visitNote(Visit v) {
  if (v.error != null) return ('Сервер не принял: ${v.error}', true);
  if (!v.sent || v.photo != null && !v.photoSent) return ('Ждёт отправки', false);
  return null;
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cream));
}

/// Почему без заказа: частая причина одним касанием или своя. Отмена — null; «без причины» — пустая строка.
Future<String?> _askReason(BuildContext context, {required bool required}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _ReasonSheet(required: required),
    );

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({required this.required});

  final bool required;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Почему без заказа?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                for (final r in VisitBook.reasons) ListTile(title: Text(r), onTap: () => Navigator.pop(context, r)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _other,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Другая причина'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: FilledButton(
                    onPressed: () {
                      if (_other.text.trim().isNotEmpty) Navigator.pop(context, _other.text.trim());
                    },
                    child: const Text('Готово'),
                  ),
                ),
                if (!widget.required)
                  TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Без причины')),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
}
