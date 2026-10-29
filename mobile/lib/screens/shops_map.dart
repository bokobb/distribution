import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/agent_data.dart';
import '../format.dart';
import '../geo.dart';
import '../location.dart';
import '../theme.dart';
import '../visits.dart';
import '../workday.dart';
import 'outlet_screen.dart';
import 'shop_facts.dart';
import 'visit_start.dart';

/// Карта магазинов по макету AgentShopsMap: вся база компании точками — обычный, был сегодня, просрочка (у своих),
/// новый на проверке; сверху поиск и фильтры с числом магазинов («Все», «Не был 7+ дней», «Просрочка», «Новые»),
/// не подходящие — серыми. Выбранный магазин — карточка снизу: «Создать заказ» и «Карточка»; по умолчанию — тот, у
/// которого торговый стоит. Подложка — OpenStreetMap, без интернета точки всё равно видны. [onList] — «Список»;
/// [pushed] — открыта поверх другого экрана: есть «Назад», заказ отправлен — закрывается с true.
class ShopsMap extends StatefulWidget {
  const ShopsMap({super.key, required this.data, required this.visits, required this.workday, this.onList, this.pushed = false});

  final AgentData data;
  final VisitBook visits;
  final Workday workday;
  final VoidCallback? onList;
  final bool pushed;

  @override
  State<ShopsMap> createState() => _ShopsMapState();
}

enum _Filter { all, stale, overdue, fresh }

class _ShopsMapState extends State<ShopsMap> {
  final _map = MapController();
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  String _query = '';
  int? _selected;
  Fix? _fix;
  bool _locating = false;
  bool _ready = false;

  /// Карту двигал человек — сама к нему не прыгает.
  bool _moved = false;

  /// Шымкент — если точек нет.
  static const _home = LatLng(42.3417, 69.5901);

  static const _fill = {
    ShopKind.regular: AppColors.accent,
    ShopKind.today: AppColors.ok,
    ShopKind.overdue: Color(0xFFE39B2D),
    ShopKind.fresh: Colors.white,
  };

  @override
  void initState() {
    super.initState();
    _fix = widget.workday.lastPlace;
    _locate();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ShopFacts get _facts => ShopFacts(data: widget.data, visits: widget.visits, fix: _fix);

  List<Outlet> get _base => widget.data.base.where((o) => o.status != 'CLOSED').toList();

  Future<void> _locate({bool show = false}) async {
    setState(() => _locating = true);
    final f = await widget.visits.location.current();
    if (!mounted) return;
    setState(() {
      _fix = f ?? _fix;
      _locating = false;
    });
    if (f == null && show) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Не удалось определить, где вы. Включите местоположение')));
    }
    final at = _fix;
    if (at != null && _ready && (show || !_moved)) _map.move(LatLng(at.lat, at.lng), 16);
  }

  bool _matches(Outlet o, ShopFacts f) {
    if (_query.trim().isNotEmpty) return ShopFacts.matches(o, _query);
    return switch (_filter) {
      _Filter.all => true,
      _Filter.stale => f.stale(o),
      _Filter.overdue => o.mine && o.overdue > 0,
      _Filter.fresh => o.pending,
    };
  }

  void _find(String q) {
    setState(() => _query = q);
    final f = _facts;
    final found = f.byDistance(_base.where((o) => _matches(o, f)));
    final sel = widget.data.outlet(_selected ?? 0);
    if (q.trim().isEmpty || found.isEmpty || sel != null && _matches(sel, f)) return;
    _select(found.first, move: true);
  }

  void _select(Outlet o, {bool move = false}) {
    setState(() => _selected = o.id);
    if (move && _ready && o.lat != null && o.lng != null) {
      _map.move(LatLng(o.lat!, o.lng!), _map.camera.zoom < 15 ? 15 : _map.camera.zoom);
    }
  }

  Future<void> _order(Outlet o) async {
    final done = await openVisit(context, data: widget.data, visits: widget.visits, workday: widget.workday, outlet: o);
    if (done && widget.pushed && mounted) Navigator.pop(context, true);
  }

  Future<void> _card(Outlet o) async {
    final done = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => OutletScreen(outlet: o, data: widget.data, visits: widget.visits, workday: widget.workday)));
    if (done == true && widget.pushed && mounted) Navigator.pop(context, true);
  }

  Future<void> _newOutlet() async {
    final done = await newOutletWithOrder(context, data: widget.data, visits: widget.visits, workday: widget.workday);
    if (done && widget.pushed && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.visits,
        builder: (context, _) {
          final f = _facts;
          final base = _base;
          final points = [for (final o in base) if (o.lat != null && o.lng != null) o];
          final searching = _query.trim().isNotEmpty;
          final found = [for (final o in base) if (_matches(o, f)) o];
          final nearest = f.byDistance(points).firstOrNull;
          final selected = _selected != null
              ? widget.data.outlet(_selected!)
              : nearest != null && f.here(nearest)
                  ? nearest
                  : null;
          final counts = {
            _Filter.all: base.length,
            _Filter.stale: base.where(f.stale).length,
            _Filter.overdue: base.where((o) => o.mine && o.overdue > 0).length,
            _Filter.fresh: base.where((o) => o.pending).length,
          };
          final fix = _fix;
          return Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: fix != null ? LatLng(fix.lat, fix.lng) : _home,
                initialZoom: fix != null ? 16 : 12,
                initialCameraFit: fix != null || points.isEmpty
                    ? null
                    : CameraFit.coordinates(
                        coordinates: [for (final o in points) LatLng(o.lat!, o.lng!)],
                        padding: const EdgeInsets.fromLTRB(48, 160, 48, 220),
                        maxZoom: 16),
                onMapReady: () => _ready = true,
                onPositionChanged: (_, gesture) {
                  if (gesture) _moved = true;
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.confectionery.distribution_mobile',
                ),
                MarkerLayer(markers: [
                  if (fix != null)
                    Marker(point: LatLng(fix.lat, fix.lng), width: 44, height: 44, child: const _Me()),
                  // не подходящие снизу, выбранный — поверх всех
                  for (final o in [
                    ...points.where((o) => !_matches(o, f)),
                    ...points.where((o) => _matches(o, f) && o.id != selected?.id),
                  ])
                    Marker(
                      point: LatLng(o.lat!, o.lng!),
                      width: 30,
                      height: 30,
                      child: _PinButton(
                        label: o.name,
                        onTap: () => _select(o),
                        child: _matches(o, f) ? _Pin(kind: f.kind(o)) : const _Pin.dim(),
                      ),
                    ),
                  if (selected?.lat != null && selected?.lng != null)
                    Marker(
                      point: LatLng(selected!.lat!, selected.lng!),
                      width: 34,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: _SelectedPin(kind: f.kind(selected)),
                    ),
                ]),
                const SimpleAttributionWidget(source: Text('OpenStreetMap')),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
                    if (widget.pushed) ...[
                      _Round(tooltip: 'Назад', icon: Icons.arrow_back, onTap: () => Navigator.maybePop(context)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: _SearchPill(controller: _search, onChanged: _find)),
                    if (widget.onList != null) ...[
                      const SizedBox(width: 8),
                      _Pill(icon: Icons.format_list_bulleted, label: 'Список', onTap: widget.onList!),
                    ],
                  ]),
                ),
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    children: [
                      for (final (filter, label) in [
                        (_Filter.all, 'Все'),
                        (_Filter.stale, 'Не был 7+ дней'),
                        (_Filter.overdue, 'Просрочка'),
                        (_Filter.fresh, 'Новые'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _FilterChip(
                            label: label,
                            count: counts[filter]!,
                            on: !searching && _filter == filter,
                            onTap: () {
                              _search.clear();
                              setState(() {
                                _query = '';
                                _filter = filter;
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (searching)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _Hint(
                      text: found.isEmpty
                          ? 'В базе такого нет'
                          : '${plural(found.length, 'магазин', 'магазина', 'магазинов')} на карте',
                      onCreate: found.isEmpty ? _newOutlet : null,
                    ),
                  ),
              ]),
            ),
            Positioned(
              right: 16,
              top: searching ? 176 : 130,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _Round(
                  tooltip: 'Показать меня',
                  icon: Icons.my_location,
                  busy: _locating,
                  onTap: () => _locate(show: true),
                ),
                const SizedBox(height: 8),
                const _Legend(),
              ]),
            ),
            if (selected != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 36, // под карточкой — подпись OpenStreetMap
                child: _SelectedCard(
                  outlet: selected,
                  facts: f,
                  onOrder: () => _order(selected),
                  onCard: () => _card(selected),
                ),
              ),
          ]);
        },
      );
}

/// Точка магазина: квадрат цвета отметки с белой рамкой; не подходит под фильтр — маленький серый.
class _Pin extends StatelessWidget {
  const _Pin({required ShopKind this.kind}) : dim = false;

  const _Pin.dim()
      : kind = null,
        dim = true;

  final ShopKind? kind;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    if (dim) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: const Color(0xFFA9AFB8),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      );
    }
    final k = kind!;
    final fresh = k == ShopKind.fresh;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: _ShopsMapState._fill[k],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fresh ? AppColors.accent : Colors.white, width: fresh ? 2.5 : 2),
        boxShadow: const [BoxShadow(color: Color(0x47101318), blurRadius: 5, offset: Offset(0, 2))],
      ),
      child: _glyph(k, 12),
    );
  }
}

Widget? _glyph(ShopKind k, double size) => switch (k) {
      ShopKind.today => Icon(Icons.check, size: size, color: Colors.white),
      ShopKind.overdue => Icon(Icons.priority_high, size: size, color: const Color(0xFF6E4100)),
      _ => null,
    };

class _PinButton extends StatelessWidget {
  const _PinButton({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: Center(child: child)),
      );
}

/// Выбранный магазин — крупная метка с хвостиком к точке.
class _SelectedPin extends StatelessWidget {
  const _SelectedPin({required this.kind});

  final ShopKind kind;

  @override
  Widget build(BuildContext context) {
    final color = kind == ShopKind.fresh ? AppColors.accent : _ShopsMapState._fill[kind]!;
    return Column(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x4D101318), blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: _glyph(kind, 18) ?? const Icon(Icons.storefront, size: 17, color: Colors.white),
      ),
      CustomPaint(size: const Size(12, 8), painter: _Tail(color)),
    ]);
  }
}

class _Tail extends CustomPainter {
  const _Tail(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Tail old) => old.color != color;
}

/// Где торговый: точка с ореолом.
class _Me extends StatelessWidget {
  const _Me();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Вы здесь',
        child: Container(
          decoration: const BoxDecoration(color: Color(0x3D4136F1), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x4D101318), blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
        ),
      );
}

const _shadow = [BoxShadow(color: Color(0x29101318), blurRadius: 10, offset: Offset(0, 2))];

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 48,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(24)), boxShadow: _shadow),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textAlignVertical: TextAlignVertical.center,
          decoration: const InputDecoration(
            hintText: 'Найти магазин',
            prefixIcon: Icon(Icons.search),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(24)), boxShadow: _shadow),
        child: TextButton.icon(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.text,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.fromLTRB(13, 0, 16, 0),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
          ),
          icon: Icon(icon, size: 20),
          label: Text(label),
        ),
      );
}

class _Round extends StatelessWidget {
  const _Round({required this.tooltip, required this.icon, required this.onTap, this.busy = false});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: _shadow),
        child: IconButton(
          tooltip: tooltip,
          onPressed: busy ? null : onTap,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 22, color: AppColors.text),
        ),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.on, required this.onTap});

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: on,
        child: Material(
          color: on ? AppColors.text : Colors.white,
          shape: const StadiumBorder(),
          elevation: 2,
          shadowColor: const Color(0x52101318),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label),
                  TextSpan(
                    text: '  $count',
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: on ? const Color(0xFFB9BEC7) : AppColors.text2,
                        fontFeatures: tabular),
                  ),
                ]),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.text),
              ),
            ),
          ),
        ),
      );
}

/// Тёмная подсказка под поиском: сколько нашлось или «Создать новый».
class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.onCreate});

  final String text;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: EdgeInsets.fromLTRB(12, 0, onCreate == null ? 12 : 4, 0),
        decoration: const BoxDecoration(
          color: AppColors.text,
          borderRadius: BorderRadius.all(Radius.circular(16)),
          boxShadow: [BoxShadow(color: Color(0x40101318), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          if (onCreate != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onCreate,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.text,
                minimumSize: const Size(0, 24),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700),
              ),
              child: const Text('Создать новый'),
            ),
          ],
        ]),
      );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(9, 8, 11, 8),
        decoration: const BoxDecoration(
          color: Color(0xF2FFFFFF),
          borderRadius: BorderRadius.all(Radius.circular(12)),
          boxShadow: _shadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (kind, label) in [
            (ShopKind.regular, 'Магазин'),
            (ShopKind.today, 'Был сегодня'),
            (ShopKind.overdue, 'Просрочка'),
            (ShopKind.fresh, 'Новый'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _ShopsMapState._fill[kind],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: kind == ShopKind.fresh ? AppColors.accent : Colors.white,
                        width: kind == ShopKind.fresh ? 2 : 1.5),
                  ),
                  child: _glyph(kind, 10),
                ),
                const SizedBox(width: 7),
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.label)),
              ]),
            ),
        ]),
      );
}

/// Карточка выбранного магазина: название, адрес, расстояние, две плашки, «Создать заказ» и «Карточка».
class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.outlet, required this.facts, required this.onOrder, required this.onCard});

  final Outlet outlet;
  final ShopFacts facts;
  final VoidCallback onOrder;
  final VoidCallback onCard;

  @override
  Widget build(BuildContext context) {
    final o = outlet;
    final m = facts.meters(o);
    final here = facts.here(o);
    final place = o.address ?? o.landmark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Color(0x6B101318), blurRadius: 32, offset: Offset(0, 12), spreadRadius: -12),
          BoxShadow(color: Color(0x14101318), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w700)),
                if (place != null || here)
                  Text([?place, if (here) 'вы у магазина'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.text2)),
              ]),
            ),
            if (m != null) ...[
              const SizedBox(width: 12),
              Text(distanceLabel(m),
                  style: TextStyle(
                      fontSize: 14,
                      height: 22 / 14,
                      fontWeight: FontWeight.w600,
                      color: here ? AppColors.accentPressed : AppColors.text2,
                      fontFeatures: tabular)),
            ],
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: facts.chips(o)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              flex: 155,
              child: FilledButton.icon(
                onPressed: onOrder,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Создать заказ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 100,
              child: TextButton(
                onPressed: onCard,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.fill,
                  foregroundColor: AppColors.text,
                  minimumSize: const Size.fromHeight(48),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                  textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
                ),
                child: const Text('Карточка'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
