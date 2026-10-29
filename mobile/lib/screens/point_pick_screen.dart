import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../location.dart';
import '../theme.dart';
import '../widgets/map_parts.dart';

/// Точка магазина вручную, когда GPS врёт или торговый стоит не у входа: карту двигают пальцем, магазин — под
/// булавкой в центре; «Где я» — вернуться к GPS. «Готово» возвращает точку под булавкой.
class PointPickScreen extends StatefulWidget {
  const PointPickScreen({super.key, required this.start, required this.location, this.here});

  /// С чего начать: уже отмеченная точка, GPS или середина базы.
  final LatLng start;
  final LocationSource location;

  /// Где телефон по GPS — синяя точка на карте.
  final LatLng? here;

  @override
  State<PointPickScreen> createState() => _PointPickScreenState();
}

class _PointPickScreenState extends State<PointPickScreen> {
  final _map = MapController();
  late LatLng _center = widget.start;
  late LatLng? _here = widget.here;
  bool _locating = false;

  Future<void> _toMe() async {
    setState(() => _locating = true);
    final fix = await widget.location.current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (fix == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('GPS не ответил — найдите магазин на карте сами')));
      return;
    }
    final me = LatLng(fix.lat, fix.lng);
    setState(() => _here = me);
    _map.move(me, 18);
  }

  @override
  Widget build(BuildContext context) {
    final here = _here;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Точка магазина'),
            Text('Двигайте карту — магазин под булавкой',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.text2)),
          ],
        ),
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.start,
            initialZoom: 18,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onPositionChanged: (camera, _) => _center = camera.center,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.confectionery.distribution_mobile',
            ),
            if (here != null) MarkerLayer(markers: [Marker(point: here, width: 44, height: 44, child: const MapMe())]),
            const SimpleAttributionWidget(source: Text('OpenStreetMap')),
          ],
        ),
        // остриё булавки — ровно в центре карты
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_on, size: 48, color: AppColors.accent, semanticLabel: 'Магазин здесь'),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 40,
          child: MapRound(tooltip: 'Где я', icon: Icons.my_location, onTap: _toMe, busy: _locating),
        ),
      ]),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _center),
              child: const Text('Магазин здесь'),
            ),
          ),
        ),
      ),
    );
  }
}
