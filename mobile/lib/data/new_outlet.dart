import 'dart:convert';

import 'agent_data.dart';

/// Новый магазин, который агент добавил с телефона. Пишется на телефон и уходит на сервер
/// (POST /api/mobile/agent/outlets), фото фасада — следом; на сервере он «на проверке» у оператора и сразу в
/// маршруте агента. uuid создаёт телефон — повтор не задвоит.
class NewOutlet {
  NewOutlet({
    required this.uuid,
    required this.createdAt,
    this.routeId,
    required this.name,
    this.legal,
    this.bin,
    this.owner,
    required this.phone,
    this.phone2,
    this.address,
    this.landmark,
    this.lat,
    this.lng,
    this.accuracy,
    this.priceKind = 'WHOLESALE',
    this.photo,
    this.sent = false,
    this.photoSent = false,
    this.error,
    this.serverId,
  });

  final String uuid;
  final DateTime createdAt;
  final int? routeId;
  final String name;
  final String? legal;
  final String? bin;
  final String? owner;
  final String phone;
  final String? phone2;
  final String? address;
  final String? landmark;

  /// Где агент отметил магазин и с какой точностью (м).
  final double? lat;
  final double? lng;
  final int? accuracy;

  /// WHOLESALE — опт, RETAIL — розница.
  final String priceKind;

  /// Файл фото фасада на телефоне.
  String? photo;
  bool sent;
  bool photoSent;

  /// Сервер не принял — почему.
  String? error;

  /// Номер магазина на сервере — когда сервер его принял.
  int? serverId;

  /// Номер на телефоне, пока сервера нет: отрицательный, свой у каждого магазина (по времени добавления). Визит и
  /// заказ в новом магазине записываются с ним и ждут, пока сервер примет магазин и даст свой номер.
  int get localId => -createdAt.millisecondsSinceEpoch;

  /// Как магазин из данных агента: свой, «на проверке», без долга.
  Outlet asOutlet() => Outlet(
        id: serverId ?? localId,
        uuid: uuid,
        name: name,
        legal: legal,
        owner: owner,
        phone: phone,
        phone2: phone2,
        address: address,
        landmark: landmark,
        lat: lat,
        lng: lng,
        priceKind: priceKind,
        creditLimit: 0,
        paymentDays: 0,
        status: 'PENDING',
        debt: 0,
        overdue: 0,
        lastPaymentSum: 0,
      );

  /// Для сервера.
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'routeId': routeId,
        'name': name,
        'legal': legal,
        'bin': bin,
        'owner': owner,
        'phone': phone,
        'phone2': phone2,
        'address': address,
        'landmark': landmark,
        'lat': lat,
        'lng': lng,
        'priceKind': priceKind,
      };

  /// Всё, что нужно хранить на телефоне, — одной строкой JSON.
  String encode() => jsonEncode({
        ...toJson(),
        'createdAt': createdAt.toIso8601String(),
        'accuracy': accuracy,
        'photo': photo,
        'sent': sent,
        'photoSent': photoSent,
        'error': error,
        'serverId': serverId,
      });

  factory NewOutlet.decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return NewOutlet(
      uuid: j['uuid'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      routeId: j['routeId'] as int?,
      name: j['name'] as String,
      legal: j['legal'] as String?,
      bin: j['bin'] as String?,
      owner: j['owner'] as String?,
      phone: j['phone'] as String,
      phone2: j['phone2'] as String?,
      address: j['address'] as String?,
      landmark: j['landmark'] as String?,
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      accuracy: j['accuracy'] as int?,
      priceKind: j['priceKind'] as String? ?? 'WHOLESALE',
      photo: j['photo'] as String?,
      sent: j['sent'] as bool? ?? false,
      photoSent: j['photoSent'] as bool? ?? false,
      error: j['error'] as String?,
      serverId: j['serverId'] as int?,
    );
  }

  NewOutlet copy() => NewOutlet.decode(encode());

  /// Телефон Казахстана: «8 701 123 45 67», «+7 (701) 123-45-67», «7011234567» — да; иначе нет (как на сервере).
  static bool phoneOk(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && (d.startsWith('8') || d.startsWith('7'))) d = d.substring(1);
    return d.length == 10;
  }
}
