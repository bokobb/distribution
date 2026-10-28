import 'dart:math';

/// Расстояние по прямой между двумя точками, метров (формула гаверсинусов — как на сервере).
int metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final h = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return (2 * r * asin(sqrt(h))).round();
}

/// «35 м», «1,2 км», «14 км».
String distanceLabel(int meters) {
  if (meters < 1000) return '$meters м';
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1).replaceAll('.', ',')} км' : '${km.round()} км';
}
