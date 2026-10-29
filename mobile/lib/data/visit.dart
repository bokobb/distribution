/// Визит агента в магазин. Начинается отметкой на месте (GPS), заканчивается заказом или «без заказа» с
/// причиной; фото полки — по желанию или по настройке компании. Пишется на телефон, на сервер уходит
/// законченным (POST /api/mobile/agent/visits), фото — следом. uuid создаёт телефон: повтор не задвоит визит.
class Visit {
  Visit({
    required this.uuid,
    required this.outletId,
    this.routeId,
    required this.startedAt,
    this.finishedAt,
    this.lat,
    this.lng,
    this.accuracy,
    this.distance,
    this.result,
    this.reason,
    this.photo,
    this.hasPhoto = false,
    this.sent = false,
    this.photoSent = false,
    this.error,
  });

  final String uuid;

  /// Новый магазин, который ещё не на сервере, — номер с телефона (минус); при отправке меняется на серверный.
  int outletId;
  final int? routeId;
  final DateTime startedAt;
  DateTime? finishedAt;

  /// Где отметился и с какой точностью (м).
  final double? lat;
  final double? lng;
  final int? accuracy;

  /// Метров до магазина при отметке; у магазина нет точки — null.
  final int? distance;

  /// ORDER или NO_ORDER; визит идёт — null.
  String? result;
  String? reason;

  /// Файл фото полки на телефоне.
  String? photo;

  /// Фото есть на сервере (визит пришёл с сервера, файла на телефоне нет).
  final bool hasPhoto;
  bool sent;
  bool photoSent;

  /// Сервер не принял — почему; такой визит больше не отправляется.
  String? error;

  bool get open => finishedAt == null;
  bool get withPhoto => photo != null || hasPhoto;

  Visit copy() => Visit(
        uuid: uuid,
        outletId: outletId,
        routeId: routeId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        distance: distance,
        result: result,
        reason: reason,
        photo: photo,
        hasPhoto: hasPhoto,
        sent: sent,
        photoSent: photoSent,
        error: error,
      );

  /// Для сервера.
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'outletId': outletId,
        'routeId': routeId,
        'startedAt': _local(startedAt),
        'finishedAt': finishedAt == null ? null : _local(finishedAt!),
        'lat': lat,
        'lng': lng,
        'result': result,
        'refuseReason': reason,
      };

  /// Визит за сегодня из данных агента с сервера — уже отправлен.
  factory Visit.fromServer(Map<String, dynamic> j) => Visit(
        uuid: j['uuid'] as String,
        outletId: j['outletId'] as int,
        startedAt: DateTime.parse(j['startedAt'] as String),
        finishedAt: j['finishedAt'] == null ? null : DateTime.parse(j['finishedAt'] as String),
        distance: j['distance'] as int?,
        result: j['result'] as String?,
        reason: j['refuseReason'] as String?,
        hasPhoto: j['photo'] as bool? ?? false,
        sent: true,
        photoSent: true,
      );

  /// Время телефона без пояса — сервер работает по времени Алматы, как и телефон.
  static String _local(DateTime t) => t.toIso8601String().split('.').first;
}
