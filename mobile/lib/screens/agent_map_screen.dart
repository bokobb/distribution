import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/agent_data.dart';
import '../format.dart';
import '../theme.dart';
import '../visits.dart';
import '../workday.dart';
import 'outlet_screen.dart';

/// Карта агента: по умолчанию точки всех магазинов компании — свои (сегодня по маршруту, уже был, остальные свои)
/// и других торговых (только название и адрес). Сверху — филиал и «Все / Мои». Подложка — OpenStreetMap, без
/// интернета точки всё равно видны. Свой магазин открывается на карточку, как с «Мой день».
class AgentMapScreen extends StatefulWidget {
  const AgentMapScreen({super.key, required this.data, required this.visits, required this.workday});

  final AgentData data;
  final VisitBook visits;
  final Workday workday;

  @override
  State<AgentMapScreen> createState() => _AgentMapScreenState();
}

class _AgentMapScreenState extends State<AgentMapScreen> {
  final _map = MapController();
  String? _region;
  bool _mine = false;
  LatLng? _me;
  bool _locating = false;

  /// Шымкент — если точек нет.
  static const _home = LatLng(42.3417, 69.5901);

  List<MapPoint> get _points => widget.data.mapPoints(region: _region, mineOnly: _mine);

  static CameraFit? _fit(List<MapPoint> points) => points.isEmpty
      ? null
      : CameraFit.coordinates(
          coordinates: [for (final p in points) LatLng(p.lat, p.lng)],
          padding: const EdgeInsets.all(48),
          maxZoom: 16);

  void _filter({String? region, bool? mine}) {
    setState(() {
      _region = region;
      _mine = mine ?? _mine;
    });
    final fit = _fit(_points);
    if (fit != null) _map.fitCamera(fit);
  }

  Future<void> _whereAmI() async {
    setState(() => _locating = true);
    final fix = await widget.visits.location.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (fix != null) _me = LatLng(fix.lat, fix.lng);
    });
    if (fix == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Не удалось определить, где вы. Включите местоположение')));
    } else {
      _map.move(_me!, 16);
    }
  }

  Color _color(MapPoint p, Set<int> today) {
    final o = p.mine;
    if (o == null) return AppColors.text2;
    final v = widget.visits.lastAt(o.id);
    if (v != null && !v.open) return AppColors.ok;
    return today.contains(o.id) ? AppColors.err : AppColors.text;
  }

  void _open(MapPoint p) {
    final o = p.mine;
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              if (p.place != null) Text(p.place!, style: const TextStyle(color: AppColors.text2)),
              Text([if (p.region != null) p.region!, o == null ? 'магазин другого торгового' : 'ваш магазин'].join(' · '),
                  style: const TextStyle(color: AppColors.text2)),
              if (o != null && o.debt > 0)
                Text('долг ${money(o.debt)}${o.overdue > 0 ? ', просрочено ${money(o.overdue)}' : ''}',
                    style: TextStyle(color: o.overdue > 0 ? AppColors.err : AppColors.text)),
              if (o != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(c);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => OutletScreen(
                                outlet: o,
                                data: widget.data,
                                routeId: widget.data.routeOf(o.id)?.id,
                                visits: widget.visits,
                                workday: widget.workday)));
                  },
                  child: const Text('Открыть магазин'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final today = {for (final r in widget.data.routesOn(DateTime.now().weekday)) ...r.outletIds};
    final noPoint = widget.data.outlets.values.where((o) => o.lat == null || o.lng == null).length;
    final regions = widget.data.regions;
    return Scaffold(
      appBar: AppBar(title: const Text('Магазины')),
      body: Column(
        children: [
          if (regions.length > 1)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                children: [
                  for (final r in [null, ...regions])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(r ?? 'Все филиалы'),
                        selected: _region == r,
                        onSelected: (_) => _filter(region: r),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Все')),
                    ButtonSegment(value: true, label: Text('Мои')),
                  ],
                  selected: {_mine},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => _filter(region: _region, mine: v.first),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    [
                      plural(points.length, 'точка', 'точки', 'точек'),
                      if (noPoint > 0) '${plural(noPoint, 'свой магазин', 'своих магазина', 'своих магазинов')} без точки',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.text2, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const _Legend(),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.visits,
              builder: (context, _) => FlutterMap(
                mapController: _map,
                options: MapOptions(initialCenter: _home, initialZoom: 12, initialCameraFit: _fit(points)),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.confectionery.distribution_mobile',
                  ),
                  MarkerLayer(markers: [
                    // чужие снизу, свои поверх
                    for (final p in [...points.where((p) => p.mine == null), ...points.where((p) => p.mine != null)])
                      Marker(
                        point: LatLng(p.lat, p.lng),
                        width: p.mine == null ? 22 : 34,
                        height: p.mine == null ? 22 : 34,
                        child: Tooltip(
                          message: p.name,
                          child: GestureDetector(
                            onTap: () => _open(p),
                            child: Icon(p.mine == null ? Icons.circle : Icons.location_on,
                                size: p.mine == null ? 14 : 34, color: _color(p, today)),
                          ),
                        ),
                      ),
                    if (_me != null)
                      Marker(
                        point: _me!,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2F4867),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                  ]),
                  const SimpleAttributionWidget(source: Text('© OpenStreetMap')),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // во вкладке рядом с кнопкой «Магазин» на «Сегодня»
        tooltip: 'Где я',
        onPressed: _locating ? null : _whereAmI,
        child: _locating
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.my_location),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Wrap(
          spacing: 12,
          children: [
            for (final (color, label) in [
              (AppColors.err, 'сегодня'),
              (AppColors.ok, 'был'),
              (AppColors.text, 'мои'),
              (AppColors.text2, 'другие'),
            ])
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              ]),
          ],
        ),
      );
}
