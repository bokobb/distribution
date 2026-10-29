import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/expeditor_data.dart';
import '../deliveries.dart';
import '../format.dart';
import '../geo.dart';
import '../launch.dart';
import '../theme.dart';
import '../workday.dart';

/// «Маршрут» экспедитора по макету ExpMap: недоставленные точки рейсов в работе с номерами по порядку и линией
/// между ними, где вы сейчас; сверху — сколько точек и километров по прямой. Внизу — следующая точка: «Поехали»
/// (карты на телефоне), звонок, «Открыть» — раскрыть её на «Доставках»; дальше по маршруту — нажать, чтобы
/// показать на карте. Подложка — OpenStreetMap, без интернета точки всё равно видны.
class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen(
      {super.key, required this.data, required this.deliveries, required this.workday, required this.onOpen});

  final ExpeditorData data;
  final DeliveryBook deliveries;
  final Workday workday;

  /// «Открыть» — точка раскрывается на «Доставках».
  final ValueChanged<Stop> onOpen;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _map = MapController();

  /// Выбранная точка — id заказа; null — следующая.
  int? _selected;

  /// Шымкент — если точек нет.
  static const _home = LatLng(42.3417, 69.5901);

  List<Stop> get _pending => [
        for (final t in widget.data.current)
          for (final s in t.stops)
            if (!widget.deliveries.done(s.order)) s
      ];

  static LatLng? _at(Stop s) => s.outlet.lat == null || s.outlet.lng == null ? null : LatLng(s.outlet.lat!, s.outlet.lng!);

  LatLng? get _me {
    final f = widget.workday.lastPlace;
    return f == null ? null : LatLng(f.lat, f.lng);
  }

  /// Сумма отрезков по прямой: от вас до первой точки и дальше по порядку.
  int _meters(List<LatLng> path) {
    var m = 0;
    for (var i = 1; i < path.length; i++) {
      m += metersBetween(path[i - 1].latitude, path[i - 1].longitude, path[i].latitude, path[i].longitude);
    }
    return m;
  }

  void _show(Stop s) {
    setState(() => _selected = s.order.id);
    final at = _at(s);
    if (at != null) _map.move(at, 15);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Маршрут')),
        body: ListenableBuilder(
          listenable: Listenable.merge([widget.deliveries, widget.workday]),
          builder: (context, _) {
            final pending = _pending;
            final placed = [for (final s in pending) if (_at(s) != null) s];
            final me = _me;
            final path = [?me, for (final s in placed) _at(s)!];
            final selected = pending.where((s) => s.order.id == _selected).firstOrNull ?? pending.firstOrNull;
            final coords = path.isEmpty ? null : path;
            return Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _home,
                    initialZoom: 12,
                    initialCameraFit: coords == null
                        ? null
                        : CameraFit.coordinates(
                            coordinates: coords,
                            padding: const EdgeInsets.fromLTRB(48, 80, 48, 280),
                            maxZoom: 16),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.confectionery.distribution_mobile',
                    ),
                    if (path.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(points: path, strokeWidth: 4, color: AppColors.accent.withValues(alpha: 0.7)),
                      ]),
                    MarkerLayer(markers: [
                      for (final s in placed.reversed)
                        Marker(
                          point: _at(s)!,
                          width: 36,
                          height: 36,
                          child: GestureDetector(
                            onTap: () => _show(s),
                            child: _Pin(number: s.position + 1, strong: s.order.id == selected?.order.id),
                          ),
                        ),
                      if (me != null)
                        Marker(
                          point: me,
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Color(0x554136F1), blurRadius: 8, spreadRadius: 4)],
                            ),
                          ),
                        ),
                    ]),
                    // внизу карточка точки — подпись карты сверху справа
                    const SimpleAttributionWidget(source: Text('© OpenStreetMap'), alignment: Alignment.topRight),
                  ],
                ),
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: const BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                        boxShadow: cardShadow,
                      ),
                      child: Text(
                        [
                          plural(pending.length, 'точка', 'точки', 'точек'),
                          if (path.length > 1) '${distanceLabel(_meters(path))} по прямой',
                          if (pending.length > placed.length) 'без точки на карте: ${pending.length - placed.length}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                if (selected != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: SafeArea(top: false, child: _NextCard(stop: selected, pending: pending, me: me, state: this)),
                  )
                else
                  const Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: SafeArea(
                      top: false,
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Все точки рейса пройдены', textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class _Pin extends StatelessWidget {
  const _Pin({required this.number, required this.strong});

  final int number;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: strong ? AppColors.accent : AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: strong ? Colors.white : AppColors.accent, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x33101318), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Text('$number',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: strong ? Colors.white : AppColors.accentPressed)),
      );
}

/// Карточка внизу карты: выбранная (по умолчанию следующая) точка и «Дальше по маршруту».
class _NextCard extends StatelessWidget {
  const _NextCard({required this.stop, required this.pending, required this.me, required this.state});

  final Stop stop;
  final List<Stop> pending;
  final LatLng? me;
  final _RouteMapScreenState state;

  String? _distance(Stop s) {
    final at = _RouteMapScreenState._at(s);
    if (me == null || at == null) return null;
    return distanceLabel(metersBetween(me!.latitude, me!.longitude, at.latitude, at.longitude));
  }

  @override
  Widget build(BuildContext context) {
    final o = stop.outlet, order = stop.order;
    final first = pending.first.order.id == order.id;
    final after = pending.skipWhile((s) => s.order.id != order.id).skip(1).take(5).toList();
    final hasPlace = o.lat != null && o.lng != null || o.address != null || o.landmark != null;
    final dist = _distance(stop);
    return Card(
      elevation: 3,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text([first ? 'Следующая точка · ${stop.position + 1}' : 'Точка ${stop.position + 1}', ?dist].join(' · '),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentPressed)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.name, style: Theme.of(context).textTheme.titleLarge),
                      if ((o.address ?? o.landmark) != null)
                        Text((o.address ?? o.landmark)!, style: const TextStyle(fontSize: 14, color: AppColors.text2)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(order.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(order.paymentLabel, style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: !hasPlace
                      ? null
                      : () => route(context, lat: o.lat, lng: o.lng, name: o.name, address: o.address ?? o.landmark),
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Поехали'),
                ),
              ),
              const SizedBox(width: 8),
              if (o.phone != null) ...[
                SizedBox(
                  width: 52,
                  child: OutlinedButton(
                    onPressed: () => call(context, o.phone!),
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(52, 52)),
                    child: const Icon(Icons.call_outlined, semanticLabel: 'Позвонить'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton(
                onPressed: () {
                  state.widget.onOpen(stop);
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 16)),
                child: const Text('Открыть'),
              ),
            ]),
            if (after.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Дальше по маршруту',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text2)),
              const SizedBox(height: 6),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final s in after)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => state._show(s),
                          borderRadius: const BorderRadius.all(Radius.circular(12)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: const BoxDecoration(
                                color: AppColors.bg, borderRadius: BorderRadius.all(Radius.circular(12))),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${s.position + 1} · ${s.outlet.name}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text(
                                    [
                                      ?_distance(s),
                                      s.order.payment == 'CREDIT' ? 'в долг' : money(s.order.total),
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
