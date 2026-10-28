import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../format.dart';
import '../outbox.dart';
import '../theme.dart';

/// «Отправка»: что на телефоне ждёт отправки (журнал и GPS, новые магазины, визиты, фото, заказы), когда
/// последний раз всё ушло и почему не уходит; «Отправить сейчас». То, что сервер не принял, — с причиной;
/// это можно убрать с телефона.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.outbox, this.outletNames = const {}});

  final Outbox outbox;

  /// id магазина → название (у агента); нет — «магазин №…».
  final Map<int, String> outletNames;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  Pending? _pending;

  @override
  void initState() {
    super.initState();
    widget.outbox.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.outbox.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await widget.outbox.store.pending();
    if (mounted) setState(() => _pending = p);
  }

  String _outlet(int id) => widget.outletNames[id] ?? 'магазин №$id';

  Future<bool> _confirmDrop(String what) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Убрать $what с телефона?'),
          content: const Text('Сервер его не принял — на сервер он не попадёт. Если нужно, сделайте заново.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Убрать')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    final o = widget.outbox;
    return Scaffold(
      appBar: AppBar(title: const Text('Отправка')),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: o,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(p.total == 0 ? 'Всё отправлено' : 'Ждут отправки: ${p.total}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          if (o.lastOk != null)
                            Text('Последняя отправка ${when(o.lastOk!)}', style: const TextStyle(color: AppColors.inkSoft)),
                          if (o.lastError != null && p.total > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('${o.lastError} — приложение повторит само',
                                  style: const TextStyle(color: AppColors.crimson)),
                            ),
                          const SizedBox(height: 8),
                          for (final (label, n) in [
                            ('Журнал и точки GPS', p.track),
                            ('Новые магазины', p.outlets),
                            ('Визиты', p.visits),
                            ('Фото', p.photos),
                            ('Заказы', p.orders),
                          ])
                            if (n > 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(children: [Expanded(child: Text(label)), Text('$n')]),
                              ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: o.sending || p.total == 0 ? null : o.flush,
                            child: Text(o.sending ? 'Отправляю…' : 'Отправить сейчас'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (p.rejectedVisits.isNotEmpty || p.rejectedOrders.isNotEmpty || p.rejectedOutlets.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Text('Сервер не принял', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.crimson)),
                    ),
                    for (final n in p.rejectedOutlets)
                      _Rejected(
                        title: 'Новый магазин · ${n.name} · ${when(n.createdAt)}',
                        error: n.error!,
                        onDrop: () async {
                          if (await _confirmDrop('магазин')) await o.dropOutlet(n);
                        },
                      ),
                    for (final v in p.rejectedVisits)
                      _Rejected(
                        title: 'Визит · ${_outlet(v.outletId)} · ${when(v.startedAt)}',
                        error: v.error!,
                        onDrop: () async {
                          if (await _confirmDrop('визит')) await o.dropVisit(v);
                        },
                      ),
                    for (final r in p.rejectedOrders)
                      _Rejected(
                        title: 'Заказ на ${money(r.total)} · ${_outlet(r.outletId)} · ${when(r.createdAt)}',
                        error: r.error!,
                        onDrop: () async {
                          if (await _confirmDrop('заказ')) await o.dropOrder(r);
                        },
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Rejected extends StatelessWidget {
  const _Rejected({required this.title, required this.error, required this.onDrop});

  final String title;
  final String error;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(title),
          subtitle: Text(error, style: const TextStyle(color: AppColors.crimson)),
          trailing: TextButton(onPressed: onDrop, child: const Text('Убрать')),
        ),
      );
}
