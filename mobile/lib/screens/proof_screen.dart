import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../camera.dart';
import '../data/expeditor_data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/layout.dart';

/// «Подтверждение доставки» по макету ExpProof — последний шаг перед «Доставлено»: сколько получено (за заказ, в счёт
/// старого долга, всего) и подтверждение от магазина — подпись получателя пальцем на экране или фото накладной с
/// подписью и печатью. «Подтвердить доставку» — только когда есть подпись или фото; возвращает путь к файлу
/// (PNG подписи или JPEG фото), он уйдёт на сервер вслед за выдачей.
class ProofScreen extends StatefulWidget {
  const ProofScreen(
      {super.key, required this.stop, required this.camera, required this.forOrder, this.oldDebt = 0});

  final Stop stop;
  final PhotoSource camera;

  /// Получено за заказ; null — в долг, оплата позже.
  final int? forOrder;

  /// Принято в счёт старого долга.
  final int oldDebt;

  @override
  State<ProofScreen> createState() => _ProofScreenState();
}

class _ProofScreenState extends State<ProofScreen> {
  bool _photoMode = false;

  /// Линии подписи в точках поля.
  final _strokes = <List<Offset>>[];
  Size _pad = Size.zero;
  String? _photo;
  DateTime? _shotAt;
  bool _busy = false;

  /// Доставку подтвердили — файл забрал экран «Доставки».
  bool _confirmed = false;

  bool get _signed => _strokes.any((s) => s.length > 1);
  bool get _ready => _photoMode ? _photo != null : _signed;

  @override
  void dispose() {
    // фото сняли, но доставку не подтвердили — файл не нужен
    if (_photo != null && !_confirmed) _drop(_photo!);
    super.dispose();
  }

  static void _drop(String path) {
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // уже нет
    }
  }

  Future<void> _shoot() async {
    final path = await widget.camera.photo('proof-${widget.stop.order.uuid}');
    if (path == null || !mounted) return;
    final was = _photo;
    setState(() {
      _photo = path;
      _shotAt = DateTime.now();
    });
    if (was != null) _drop(was);
  }

  /// Подпись — PNG на белом, вдвое чётче экрана.
  Future<String> _signature() async {
    const scale = 2.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(scale);
    canvas.drawRect(Offset.zero & _pad, Paint()..color = Colors.white);
    _Ink.draw(canvas, _strokes);
    final image = await rec.endRecording().toImage((_pad.width * scale).ceil(), (_pad.height * scale).ceil());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return widget.camera.keep(
        'proof-${widget.stop.order.uuid}-${DateTime.now().millisecondsSinceEpoch}.png', png!.buffer.asUint8List());
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final path = _photoMode ? _photo! : await _signature();
    if (!mounted) return;
    _confirmed = true;
    // сняли фото, а подтвердили подписью — фото не нужно
    if (!_photoMode && _photo != null) _drop(_photo!);
    Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stop, o = s.outlet, order = s.order;
    final forOrder = widget.forOrder;
    // без прокрутки: подпись пальцем не должна двигать экран, поле подписи — всё оставшееся место
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Подтверждение доставки'),
          Text([o.name, 'Заказ ${order.number}'].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text2)),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: _Sum('За заказ', forOrder == null ? 'в долг' : money(forOrder))),
                        if (widget.oldDebt > 0) ...[
                          const VerticalDivider(width: 20),
                          Expanded(child: _Sum('Старый долг', money(widget.oldDebt))),
                          if (forOrder != null) ...[
                            const VerticalDivider(width: 20),
                            Expanded(child: _Sum('Всего', money(forOrder + widget.oldDebt), strong: true)),
                          ],
                        ],
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PillTabs(
                  labels: const ['Подпись на экране', 'Фото накладной'],
                  index: _photoMode ? 1 : 0,
                  onChanged: (i) => setState(() => _photoMode = i == 1),
                ),
                const SizedBox(height: 12),
                Expanded(child: _photoMode ? _photoCard() : _signCard()),
              ]),
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
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (_ready) ...[
                      const Icon(Icons.check_circle_outline, size: 16, color: AppColors.ok),
                      const SizedBox(width: 6),
                    ],
                    Text(
                        _ready
                            ? (_photoMode ? 'Фото накладной приложено' : 'Подпись получена')
                            : (_photoMode ? 'Нужно фото накладной с печатью' : 'Нужна подпись получателя'),
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: _ready ? AppColors.ok : AppColors.text2)),
                  ]),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: _ready && !_busy ? _confirm : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Подтвердить доставку'),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _head(String title, {Widget? action}) => SizedBox(
        height: 44,
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ?action,
        ]),
      );

  Widget _signCard() => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 6, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _head('Подпись получателя',
                action: TextButton(
                  onPressed: _signed ? () => setState(_strokes.clear) : null,
                  style: TextButton.styleFrom(foregroundColor: AppColors.accent, minimumSize: const Size(0, 36)),
                  child: const Text('Очистить'),
                )),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Semantics(
                  label: 'Поле подписи',
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      border: Border.all(color: _signed ? AppColors.field : const Color(0xFFB4B9C2), width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(13)),
                      child: LayoutBuilder(builder: (context, c) {
                        _pad = Size(c.maxWidth, c.maxHeight);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                          onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                          child: CustomPaint(
                            painter: _Ink(_strokes),
                            child: Stack(children: [
                              // линия, на которой расписываются
                              const Positioned(
                                left: 20,
                                right: 20,
                                bottom: 28,
                                child: Row(children: [
                                  Text('×', style: TextStyle(fontSize: 18, color: AppColors.icon)),
                                  SizedBox(width: 6),
                                  Expanded(child: Divider(color: AppColors.field, thickness: 1.5)),
                                ]),
                              ),
                              if (!_signed)
                                const Center(
                                  child: Text('Распишитесь здесь пальцем',
                                      style: TextStyle(fontSize: 15, color: AppColors.icon)),
                                ),
                            ]),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Получил: ${widget.stop.outlet.owner ?? widget.stop.outlet.name}',
                style: const TextStyle(fontSize: 13, color: AppColors.text2)),
          ]),
        ),
      );

  Widget _photoCard() {
    final photo = _photo;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 6, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _head('Накладная с подписью и печатью',
              action: photo == null
                  ? null
                  : TextButton(
                      onPressed: _shoot,
                      style: TextButton.styleFrom(foregroundColor: AppColors.accent, minimumSize: const Size(0, 36)),
                      child: const Text('Переснять'),
                    )),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: photo == null
                  ? InkWell(
                      onTap: _shoot,
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: const BorderRadius.all(Radius.circular(14)),
                          border: Border.all(color: const Color(0xFFB4B9C2), width: 1.5),
                        ),
                        child: const Center(
                          child: SingleChildScrollView(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppColors.accentSoft,
                                child: Icon(Icons.photo_camera_outlined, color: AppColors.accentPressed),
                              ),
                              SizedBox(height: 10),
                              Text('Сфотографировать накладную',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              SizedBox(height: 2),
                              Text('Чтобы в кадре были подпись и печать магазина',
                                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.text2)),
                            ]),
                          ),
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      child: Image.file(File(photo),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              color: AppColors.fill,
                              alignment: Alignment.center,
                              child: const Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.icon))),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
              photo == null
                  ? 'Фото уйдёт в офис вместе с отметкой о доставке'
                  : 'Снято в ${time(_shotAt!)} · фото уйдёт в офис вместе с отметкой о доставке',
              style: const TextStyle(fontSize: 13, color: AppColors.text2)),
        ]),
      ),
    );
  }
}

/// Сумма в строке сверху: подпись и значение.
class _Sum extends StatelessWidget {
  const _Sum(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontSize: strong ? 17 : 15,
                  fontWeight: FontWeight.w700,
                  color: strong ? AppColors.text : AppColors.label,
                  fontFeatures: tabular)),
        ),
      ]);
}

/// Подпись: линии пальца, скруглённые.
class _Ink extends CustomPainter {
  _Ink(this.strokes);

  final List<List<Offset>> strokes;

  static void draw(Canvas canvas, List<List<Offset>> strokes) {
    final pen = Paint()
      ..color = AppColors.text
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, strokes);

  // линии дописываются в тот же список — перерисовывать всегда
  @override
  bool shouldRepaint(_Ink old) => true;
}
