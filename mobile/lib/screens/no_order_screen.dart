import 'package:flutter/material.dart';

import '../data/agent_data.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/shelf_photo.dart';

/// «Без заказа» по макету AgentNoOrder: почему сегодня без заказа (частая причина или «Другая причина» своими
/// словами), фото полки (обязательно — если так в настройках), комментарий; «Завершить визит» заканчивает идущий
/// визит. Закончили — возвращает true.
class NoOrderScreen extends StatefulWidget {
  const NoOrderScreen({super.key, required this.outlet, required this.data, required this.visits});

  final Outlet outlet;
  final AgentData data;
  final VisitBook visits;

  @override
  State<NoOrderScreen> createState() => _NoOrderScreenState();
}

class _NoOrderScreenState extends State<NoOrderScreen> {
  static const _other = 'Другая причина';

  String? _reason;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Что уйдёт на сервер: причина, а комментарий — через тире; «Другая причина» — сам комментарий.
  String? get _text {
    final c = _comment.text.trim();
    if (_reason == _other) return c.isEmpty ? null : c;
    if (_reason == null) return c.isEmpty ? null : c;
    return c.isEmpty ? _reason : '$_reason — $c';
  }

  Future<void> _finish() async {
    final s = widget.data.settings;
    if (_reason == _other && _comment.text.trim().isEmpty) return _say('Напишите причину в комментарии');
    if (s.refuseReasonRequired && _text == null) return _say('Выберите, почему без заказа');
    setState(() => _busy = true);
    try {
      final problem = await widget.visits.finishNoOrder(_text, s);
      if (!mounted) return;
      if (problem != null) return _say(problem);
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.outlet;
    final text = Theme.of(context).textTheme;
    final reasons = [...VisitBook.reasons, _other];
    return Scaffold(
      appBar: AppBar(title: const Text('Без заказа')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.name, style: text.headlineSmall),
                const SizedBox(height: 2),
                Text([?(o.address ?? o.landmark), 'почему сегодня без заказа?'].join(' · '),
                    style: const TextStyle(fontSize: 15, color: AppColors.text2)),
              ],
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final (i, r) in reasons.indexed) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 0),
                    Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: _reason == r,
                      child: InkWell(
                        onTap: () => setState(() => _reason = r),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              Expanded(
                                child: Text(r,
                                    style: TextStyle(
                                        fontSize: 15, fontWeight: _reason == r ? FontWeight.w600 : FontWeight.w400)),
                              ),
                              _Ring(on: _reason == r),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ShelfPhotoButton(visits: widget.visits, required: widget.data.settings.shelfPhotoRequired),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text('Комментарий', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.label)),
          ),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            maxLength: 150,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _reason == _other ? 'Напишите причину' : 'Необязательно: когда зайти снова',
              counterText: '',
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: _busy ? null : _finish,
              child: const Text('Завершить визит'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кружок выбора: выбран — толстое индиго кольцо.
class _Ring extends StatelessWidget {
  const _Ring({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          border: on ? Border.all(color: AppColors.accent, width: 7) : Border.all(color: const Color(0xFFC9CDD5), width: 2),
        ),
      );
}
