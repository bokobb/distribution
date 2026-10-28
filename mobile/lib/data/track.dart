/// Запись журнала приложения: начал и закончил день, открыл приложение, GPS выключен и включён. uuid создаёт
/// телефон — повторная отправка на сервере дубля не создаёт.
class TrackEvent {
  const TrackEvent({required this.uuid, required this.at, required this.kind, this.note});

  final String uuid;
  final DateTime at;

  /// Имя из AppEventKind на сервере: APP_OPEN, DAY_START, DAY_END, SYNC, GPS_OFF, GPS_ON.
  final String kind;
  final String? note;

  Map<String, dynamic> toJson({String? appVersion, String? device}) => {
        'uuid': uuid,
        'at': at.toIso8601String(),
        'kind': kind,
        'appVersion': appVersion,
        'device': device,
        'note': note,
      };
}

/// Точка GPS: время снятия, координаты, точность (м) и заряд (%), если телефон их знает.
class TrackPoint {
  const TrackPoint({required this.at, required this.lat, required this.lng, this.accuracy, this.battery});

  final DateTime at;
  final double lat;
  final double lng;
  final int? accuracy;
  final int? battery;

  Map<String, dynamic> toJson() =>
      {'at': at.toIso8601String(), 'lat': lat, 'lng': lng, 'accuracy': accuracy, 'battery': battery};
}

/// Неотправленное — пачкой для сервера.
class TrackBatch {
  const TrackBatch(this.events, this.points);

  final List<TrackEvent> events;
  final List<TrackPoint> points;

  int get size => events.length + points.length;
}
