import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/agent_data.dart';
import '../data/track.dart';
import '../data/visit.dart';
import '../format.dart';
import '../geo.dart';
import '../theme.dart';
import '../visits.dart';
import '../widgets/map_parts.dart';
import '../workday.dart';

/// «Мой путь» по макету AgentMap: путь за рабочий день по точкам GPS с телефона, визиты по порядку номерами (заказ,
/// без заказа, новый магазин), начало дня, где торговый сейчас, и магазины базы. Снизу — сколько визитов и заказов,
/// сколько в работе и лента дня, свежее сверху. Путь пишется сам, пока открыт рабочий день.
class MyPathScreen extends StatefulWidget {
  const MyPathScreen({super.key, required this.data, required this.visits, required this.workday, DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final AgentData? data;
  final VisitBook visits;
  final Workday workday;
  final DateTime Function() _now;

  @override
  State<MyPathScreen> createState() => _MyPathScreenState();
}

class _MyPathScreenState extends State<MyPathScreen> {
  final _map = MapController();
  List<TrackPoint> _points = const [];

  /// Точки прочитаны — карта сразу показывает весь путь.
  bool _loaded = false;
  DateTime? _loadedFix;
  bool _ready = false;
  double _sheet = _sheetStart;

  /// Точки хуже этой точности в путь не идут — дёргают линию.
  static const _maxAccuracy = 100;
  static const _sheetStart = 0.4;

  /// Шымкент — если точек нет.
  static const _home = LatLng(42.3417, 69.5901);

  @override
  void initState() {
    super.initState();
    widget.workday.addListener(_fixChanged);
    _load();
  }

  @override
  void dispose() {
    widget.workday.removeListener(_fixChanged);
    super.dispose();
  }

  DateTime get _from {
    final n = widget._now();
    return widget.workday.startedAt ?? DateTime(n.year, n.month, n.day);
  }

  /// Новая точка GPS — путь длиннее.
  void _fixChanged() {
    if (widget.workday.lastFix != _loadedFix) unawaited(_load());
  }

  Future<void> _load() async {
    _loadedFix = widget.workday.lastFix;
    final points = await widget.visits.store.pointsSince(_from);
    if (!mounted) return;
    setState(() {
      _points = [for (final p in points) if ((p.accuracy ?? 0) <= _maxAccuracy) p];
      _loaded = true;
    });
  }

  LatLng? get _me {
    final f = widget.workday.lastPlace;
    if (f != null) return LatLng(f.lat, f.lng);
    final p = _points.lastOrNull;
    return p == null ? null : LatLng(p.lat, p.lng);
  }

  int get _meters {
    var m = 0;
    for (var i = 1; i < _points.length; i++) {
      m += metersBetween(_points[i - 1].lat, _points[i - 1].lng, _points[i].lat, _points[i].lng);
    }
    return m;
  }

  /// Где был визит: точка визита, нет — точка магазина.
  LatLng? _at(Visit v) {
    if (v.lat != null && v.lng != null) return LatLng(v.lat!, v.lng!);
    final o = widget.data?.outlet(v.outletId);
    return o?.lat != null && o?.lng != null ? LatLng(o!.lat!, o.lng!) : null;
  }

  bool _isNew(Visit v) => widget.data?.outlet(v.outletId)?.pending == true;

  String _name(Visit v) => widget.data?.outlet(v.outletId)?.name ?? 'Магазин';

  void _showMe() {
    final me = _me;
    if (me == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Где вы — пока неизвестно: точка GPS ещё не пришла')));
      return;
    }
    if (_ready) _map.move(me, _map.camera.zoom < 15 ? 15 : _map.camera.zoom);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: !_loaded ? const Center(child: CircularProgressIndicator()) : ListenableBuilder(
          listenable: Listenable.merge([widget.visits, widget.workday]),
          builder: (context, _) {
            final day = [for (final v in widget.visits.today) if (!v.startedAt.isBefore(_from)) v];
            final done = [for (final v in day) if (!v.open) v];
            final current = day.where((v) => v.open).firstOrNull;
            final me = _me;
            final track = [for (final p in _points) LatLng(p.lat, p.lng)];
            final visited = {for (final v in day) v.outletId};
            final base = [
              for (final o in widget.data?.base ?? const <Outlet>[])
                if (o.lat != null && o.lng != null && o.status != 'CLOSED' && !visited.contains(o.id)) o
            ];
            final fit = [...track, for (final v in done) ?_at(v), ?me];
            final height = MediaQuery.sizeOf(context).height;
            return Stack(children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: me ?? _home,
                  initialZoom: me != null ? 15 : 12,
                  initialCameraFit: fit.length < 2
                      ? null
                      : CameraFit.coordinates(
                          coordinates: fit,
                          padding: EdgeInsets.fromLTRB(40, 110, 40, height * _sheetStart + 24),
                          maxZoom: 16),
                  onMapReady: () => _ready = true,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.confectionery.distribution_mobile',
                  ),
                  MarkerLayer(markers: [
                    for (final o in base)
                      Marker(point: LatLng(o.lat!, o.lng!), width: 13, height: 13, child: const _BaseShop()),
                  ]),
                  if (track.length > 1)
                    PolylineLayer(polylines: [
                      Polyline(points: track, color: Colors.white, strokeWidth: 9, strokeCap: StrokeCap.round, strokeJoin: StrokeJoin.round),
                      Polyline(
                          points: track,
                          color: AppColors.accent.withValues(alpha: 0.9),
                          strokeWidth: 4.5,
                          strokeCap: StrokeCap.round,
                          strokeJoin: StrokeJoin.round),
                    ]),
                  MarkerLayer(markers: [
                    if (track.isNotEmpty)
                      Marker(
                          point: track.first,
                          width: 20,
                          height: 20,
                          child: Semantics(label: 'Начало дня, ${time(_points.first.at)}', child: const _Start())),
                    for (final (i, v) in done.indexed)
                      if (_at(v) case final at?)
                        Marker(point: at, width: 26, height: 26, child: _Number(n: i + 1, kind: _kind(v), big: true)),
                    if (me != null) Marker(point: me, width: 44, height: 44, child: const MapMe()),
                    if (me != null && current != null)
                      Marker(
                        point: me,
                        width: 240,
                        height: 26,
                        alignment: Alignment.centerLeft,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: _Label('Вы у ${_name(current)} · ${time(current.startedAt)}'),
                          ),
                        ),
                      ),
                  ]),
                  const SimpleAttributionWidget(source: Text('OpenStreetMap')),
                ],
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(children: [
                    MapRound(tooltip: 'Назад', icon: Icons.arrow_back, onTap: () => Navigator.maybePop(context)),
                    const SizedBox(width: 10),
                    Expanded(child: _TitlePill(meters: track.length > 1 ? _meters : null, from: _from)),
                  ]),
                ),
              ),
              Positioned(
                right: 16,
                bottom: height * _sheet + 16,
                child: MapRound(tooltip: 'Показать меня', icon: Icons.my_location, onTap: _showMe),
              ),
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  setState(() => _sheet = n.extent);
                  return false;
                },
                child: DraggableScrollableSheet(
                  initialChildSize: _sheetStart,
                  minChildSize: 0.22,
                  maxChildSize: 0.85,
                  builder: (context, scroll) => _Sheet(
                    scroll: scroll,
                    done: done,
                    current: current,
                    startedAt: widget.workday.startedAt,
                    endedAt: widget.workday.open ? null : widget.workday.endedAt,
                    now: widget._now(),
                    visits: widget.visits,
                    data: widget.data,
                    kind: _kind,
                  ),
                ),
              ),
            ]);
          },
        ),
      );

  _Kind _kind(Visit v) {
    if (v.result == 'ORDER') return _isNew(v) ? _Kind.fresh : _Kind.order;
    return _Kind.noOrder;
  }
}

enum _Kind { order, noOrder, fresh }

/// Шторка снизу: итоги, легенда, лента дня.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.scroll,
    required this.done,
    required this.current,
    required this.startedAt,
    required this.endedAt,
    required this.now,
    required this.visits,
    required this.data,
    required this.kind,
  });

  final ScrollController scroll;
  final List<Visit> done;
  final Visit? current;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime now;
  final VisitBook visits;
  final AgentData? data;
  final _Kind Function(Visit) kind;

  @override
  Widget build(BuildContext context) {
    final orders = done.where((v) => v.result == 'ORDER').length;
    final start = startedAt;
    final rows = <Widget>[
      if (current case final v?)
        _Row(
          time: time(v.startedAt),
          now: true,
          icon: const _CurrentDot(),
          name: 'Сейчас у ${data?.outlet(v.outletId)?.name ?? 'магазина'}',
          tail: data?.outlet(v.outletId)?.address,
        ),
      for (final (i, v) in done.indexed.toList().reversed)
        _Row(
          time: time(v.startedAt),
          icon: _Number(n: i + 1, kind: kind(v)),
          name: data?.outlet(v.outletId)?.name ?? 'Магазин',
          tail: _result(v),
        ),
      if (start != null)
        _Row(
            time: time(start),
            icon: Center(
                child: Container(
                    width: 12,
                    height: 12,
                    decoration:
                        const BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.all(Radius.circular(3))))),
            name: 'Начало рабочего дня'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x40101318), blurRadius: 30, offset: Offset(0, -8), spreadRadius: -12)],
      ),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          Center(
            child: Container(
                width: 36,
                height: 5,
                decoration:
                    const BoxDecoration(color: Color(0xFFD5D9E0), borderRadius: BorderRadius.all(Radius.circular(3)))),
          ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(
              child: Text(
                  '${plural(done.length, 'визит', 'визита', 'визитов')} · ${plural(orders, 'заказ', 'заказа', 'заказов')}',
                  style: const TextStyle(fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w700)),
            ),
            if (start != null)
              Text('в работе ${_span((endedAt ?? now).difference(start))}',
                  style: const TextStyle(fontSize: 13, color: AppColors.text2)),
          ]),
          const SizedBox(height: 6),
          const Wrap(spacing: 14, runSpacing: 4, children: [
            _Legend(kind: _LegendKind.order, label: 'Заказ'),
            _Legend(kind: _LegendKind.noOrder, label: 'Без заказа'),
            _Legend(kind: _LegendKind.fresh, label: 'Новый магазин'),
            _Legend(kind: _LegendKind.start, label: 'Начало дня'),
            _Legend(kind: _LegendKind.base, label: 'Магазины из базы'),
          ]),
          const SizedBox(height: 8),
          for (final (i, r) in rows.indexed)
            Container(
              decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
              child: r,
            ),
          const SizedBox(height: 10),
          const Text('Путь пишется сам, пока идёт рабочий день. Руководитель видит его в админке на карте.',
              style: TextStyle(fontSize: 13, height: 18 / 13, color: AppColors.text2)),
        ],
      ),
    );
  }

  /// «заказ 21 300 ₸», «новый, заказ 15 600 ₸», «заказ 41 300 ₸, возврат 2 280 ₸», «без заказа».
  String _result(Visit v) {
    if (v.error != null) return 'сервер не принял';
    if (v.result != 'ORDER') return 'без заказа';
    final o = visits.orderOf(v);
    final k = kind(v);
    if (o == null) return k == _Kind.fresh ? 'новый, заказ' : 'заказ';
    return [
      '${k == _Kind.fresh ? 'новый, заказ' : 'заказ'} ${money(o.total)}',
      if (o.returnTotal > 0) 'возврат ${money(o.returnTotal)}',
    ].join(', ');
  }

  /// «2 ч 50 мин», «25 мин».
  static String _span(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h == 0 ? '$m мин' : '$h ч $m мин';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.time, required this.icon, required this.name, this.tail, this.now = false});

  final String time;
  final Widget icon;
  final String name;
  final String? tail;
  final bool now;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(
              width: 40,
              child: Text(time,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: now ? FontWeight.w600 : FontWeight.w400,
                      color: now ? AppColors.accentPressed : AppColors.text2,
                      fontFeatures: tabular)),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 20, height: 20, child: icon),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (tail != null && tail!.isNotEmpty)
                    TextSpan(text: ' · $tail', style: const TextStyle(color: AppColors.text2)),
                ]),
                style: const TextStyle(fontSize: 14, fontFeatures: tabular),
              ),
            ),
          ]),
        ),
      );
}

/// Номер визита: зелёный — заказ, белый с серой рамкой — без заказа, фирменный — новый магазин.
class _Number extends StatelessWidget {
  const _Number({required this.n, required this.kind, this.big = false});

  final int n;
  final _Kind kind;

  /// На карте — крупнее, с белой рамкой и тенью.
  final bool big;

  @override
  Widget build(BuildContext context) {
    final fill = switch (kind) { _Kind.order => AppColors.ok, _Kind.fresh => AppColors.accent, _Kind.noOrder => Colors.white };
    final plain = kind == _Kind.noOrder;
    return Container(
      width: big ? 26 : 20,
      height: big ? 26 : 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: plain || big ? Border.all(color: plain ? const Color(0xFF9AA1AB) : Colors.white, width: 2) : null,
        boxShadow: big
            ? [
                BoxShadow(
                    color: kind == _Kind.fresh ? const Color(0x664136F1) : const Color(0x40101318),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]
            : null,
      ),
      child: Text('$n',
          style: TextStyle(
              fontSize: big ? 12 : 11, fontWeight: FontWeight.w700, color: plain ? AppColors.text2 : Colors.white, height: 1)),
    );
  }
}

/// Начало дня на карте: чёрный квадрат с белой рамкой.
class _Start extends StatelessWidget {
  const _Start();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.text,
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x4D101318), blurRadius: 4, offset: Offset(0, 1))],
          ),
        ),
      );
}

/// Магазин из базы: маленький сиреневый квадрат.
class _BaseShop extends StatelessWidget {
  const _BaseShop();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFA9A4F7),
          borderRadius: const BorderRadius.all(Radius.circular(3)),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x2E101318), blurRadius: 2, offset: Offset(0, 1))],
        ),
      );
}

/// Идущий визит в ленте: синяя точка с ореолом.
class _CurrentDot extends StatelessWidget {
  const _CurrentDot();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 15,
          height: 15,
          decoration: const BoxDecoration(color: Color(0x404136F1), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
                color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          ),
        ),
      );
}

/// «Вы у «Нур» · 11:02» рядом с точкой торгового.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(13)),
          boxShadow: [BoxShadow(color: Color(0x2E101318), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Center(
            widthFactor: 1,
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
      );
}

/// «Мой путь · 6,4 км · с 08:12».
class _TitlePill extends StatelessWidget {
  const _TitlePill({required this.meters, required this.from});

  final int? meters;
  final DateTime from;

  @override
  Widget build(BuildContext context) {
    const dot = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
          width: 3, height: 3, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF8C929C), shape: BoxShape.circle))),
    );
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(22)), boxShadow: mapShadow),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Мой путь', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        if (meters != null) ...[
          dot,
          Text(distanceLabel(meters!), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ],
        dot,
        Text('с ${time(from)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text2)),
      ]),
    );
  }
}

enum _LegendKind { order, noOrder, fresh, start, base }

class _Legend extends StatelessWidget {
  const _Legend({required this.kind, required this.label});

  final _LegendKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final mark = switch (kind) {
      _LegendKind.order => const BoxDecoration(color: AppColors.ok, shape: BoxShape.circle),
      _LegendKind.noOrder =>
        BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF9AA1AB), width: 2)),
      _LegendKind.fresh => const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
      _LegendKind.start => const BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.all(Radius.circular(2))),
      _LegendKind.base => const BoxDecoration(color: Color(0xFFA9A4F7), borderRadius: BorderRadius.all(Radius.circular(3))),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: mark),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
    ]);
  }
}
