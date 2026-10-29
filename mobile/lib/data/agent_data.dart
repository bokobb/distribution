import 'new_outlet.dart';
import 'order.dart';
import 'visit.dart';

/// Данные торгового агента с сервера (/api/mobile/agent/data): настройки компании, товары с ценами на день
/// синхронизации, маршруты агента, его магазины с долгами, его визиты и заказы за этот день, остальные магазины
/// компании (заказ принимают в любом — без долгов), последний заказ каждого магазина и сводка по магазинам для карты.
/// Хранятся на телефоне целиком, обновляются целиком. К ним добавляются новые магазины с телефона ([withLocal]).
class AgentData {
  AgentData._(this.json, this.date, this.syncedAt, this.settings, this.products, this.routes, this.outlets,
      this.visits, this.orders, this.others, this.lastOrders, this.stats,
      [this.local = const []]);

  /// Как пришло с сервера — так и хранится на телефоне.
  final Map<String, dynamic> json;

  /// День на сервере, на который посчитаны цены и долги.
  final DateTime date;
  final DateTime syncedAt;
  final AgentSettings settings;
  final List<Product> products;
  final List<RouteInfo> routes;
  final Map<int, Outlet> outlets;

  /// Визиты и заказы агента за день синхронизации, которые уже на сервере.
  final List<Visit> visits;
  final List<Order> orders;

  /// Магазины других торговых: название, адрес, прайс — без долгов.
  final List<Place> others;

  /// Последний заказ магазина: id магазина → заказ.
  final Map<int, LastOrder> lastOrders;

  /// Последний визит, средний заказ, день в базе: id магазина → сводка.
  final Map<int, OutletStat> stats;

  /// Новые магазины с телефона (не отклонённые сервером).
  final List<NewOutlet> local;

  Product? product(int id) => products.where((p) => p.id == id).firstOrNull;

  /// Вся база: свои магазины, чужие (без долгов) и новые с телефона, которых в данных с сервера ещё нет.
  late final List<Outlet> base = [
    ...outlets.values,
    for (final p in others) p.asOutlet(),
    for (final n in local)
      if (n.serverId == null || !outlets.containsKey(n.serverId) && !others.any((p) => p.id == n.serverId)) n.asOutlet(),
  ];

  /// id → магазин; новый магазин находится и по номеру с телефона — визит начат до того, как его принял сервер.
  late final Map<int, Outlet> _byId = () {
    final byId = {for (final o in base) o.id: o};
    for (final n in local) {
      final o = byId[n.serverId ?? n.localId];
      if (o != null) byId[n.localId] = o;
    }
    return byId;
  }();

  /// Магазин из всей базы.
  Outlet? outlet(int id) => _byId[id];

  /// Те же данные с новыми магазинами с телефона.
  AgentData withLocal(List<NewOutlet> list) => AgentData._(json, date, syncedAt, settings, products, routes, outlets,
      visits, orders, others, lastOrders, stats, [for (final n in list) if (n.error == null) n]);

  factory AgentData.fromJson(Map<String, dynamic> json) {
    final outlets = <int, Outlet>{};
    for (final o in json['outlets'] as List) {
      final outlet = Outlet.fromJson(o as Map<String, dynamic>);
      outlets[outlet.id] = outlet;
    }
    return AgentData._(
      json,
      DateTime.parse(json['date'] as String),
      DateTime.parse(json['syncedAt'] as String),
      AgentSettings.fromJson(json['settings'] as Map<String, dynamic>),
      [for (final p in json['products'] as List) Product.fromJson(p as Map<String, dynamic>)],
      [for (final r in json['routes'] as List) RouteInfo.fromJson(r as Map<String, dynamic>)],
      outlets,
      [for (final v in json['visits'] as List? ?? const []) Visit.fromServer(v as Map<String, dynamic>)],
      [for (final o in json['orders'] as List? ?? const []) Order.fromServer(o as Map<String, dynamic>)],
      [for (final p in json['others'] as List? ?? const []) Place.fromJson(p as Map<String, dynamic>)],
      {
        for (final l in json['lastOrders'] as List? ?? const [])
          (l as Map<String, dynamic>)['outletId'] as int: LastOrder.fromJson(l),
      },
      {
        for (final st in json['stats'] as List? ?? const [])
          (st as Map<String, dynamic>)['outletId'] as int: OutletStat.fromJson(st),
      },
    );
  }

  /// Первый маршрут агента, в котором есть магазин.
  RouteInfo? routeOf(int outletId) => routes.where((r) => r.outletIds.contains(outletId)).firstOrNull;
}

/// Магазин другого торгового: название, адрес, владелец, прайс и точка (может не быть), без долгов и телефонов.
class Place {
  const Place(
      {required this.id,
      required this.name,
      this.address,
      this.landmark,
      this.lat,
      this.lng,
      this.region,
      this.owner,
      this.priceKind = 'WHOLESALE',
      this.status = 'ACTIVE'});

  final int id;
  final String name;
  final String? address;
  final String? landmark;
  final double? lat;
  final double? lng;

  /// Филиал.
  final String? region;
  final String? owner;
  final String priceKind;
  final String status;

  /// Для заказа: долгов не знаем — нули, [Outlet.mine] = false.
  Outlet asOutlet() => Outlet(
        id: id,
        uuid: '',
        name: name,
        owner: owner,
        address: address,
        landmark: landmark,
        lat: lat,
        lng: lng,
        priceKind: priceKind,
        creditLimit: 0,
        paymentDays: 0,
        status: status,
        debt: 0,
        overdue: 0,
        lastPaymentSum: 0,
        mine: false,
      );

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as int,
        name: j['name'] as String,
        address: j['address'] as String?,
        landmark: j['landmark'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        region: j['region'] as String?,
        owner: j['owner'] as String?,
        priceKind: j['priceKind'] as String? ?? 'WHOLESALE',
        status: j['status'] as String? ?? 'ACTIVE',
      );
}

/// Последний заказ магазина: день и товары (id → штук) — «Как 21 октября».
class LastOrder {
  const LastOrder({required this.date, required this.items});

  final DateTime date;
  final Map<int, int> items;

  factory LastOrder.fromJson(Map<String, dynamic> j) => LastOrder(
        date: DateTime.parse(j['date'] as String),
        items: {for (final i in j['items'] as List) (i as Map)['productId'] as int: i['qty'] as int},
      );
}

/// Сводка по магазину для карты и списка: когда в нём последний раз были (любой торговый), средний заказ за 90 дней
/// (0 — заказов не было) и с какого дня он в базе.
class OutletStat {
  const OutletStat({this.lastVisit, required this.avgOrder, required this.createdOn});

  final DateTime? lastVisit;
  final int avgOrder;
  final DateTime createdOn;

  factory OutletStat.fromJson(Map<String, dynamic> j) => OutletStat(
        lastVisit: j['lastVisit'] == null ? null : DateTime.parse(j['lastVisit'] as String),
        avgOrder: j['avgOrder'] as int,
        createdOn: DateTime.parse(j['createdOn'] as String),
      );
}

class AgentSettings {
  const AgentSettings({
    required this.visitRadius,
    required this.shelfPhotoRequired,
    required this.refuseReasonRequired,
    required this.deliveryDays,
    required this.allowCredit,
    required this.approvalOverLimit,
    required this.agentDiscount,
    required this.acceptKaspi,
    required this.gpsInterval,
  });

  /// «Агент на месте», если до магазина не дальше стольких метров.
  final int visitRadius;
  final bool shelfPhotoRequired;
  final bool refuseReasonRequired;

  /// Доставка по умолчанию — через столько дней после заказа.
  final int deliveryDays;
  final bool allowCredit;
  final bool approvalOverLimit;
  final bool agentDiscount;
  final bool acceptKaspi;

  /// Точка GPS — раз в столько минут рабочего дня.
  final int gpsInterval;

  factory AgentSettings.fromJson(Map<String, dynamic> j) => AgentSettings(
        visitRadius: j['visitRadius'] as int,
        shelfPhotoRequired: j['shelfPhotoRequired'] as bool,
        refuseReasonRequired: j['refuseReasonRequired'] as bool,
        deliveryDays: j['deliveryDays'] as int,
        allowCredit: j['allowCredit'] as bool,
        approvalOverLimit: j['approvalOverLimit'] as bool,
        agentDiscount: j['agentDiscount'] as bool,
        acceptKaspi: j['acceptKaspi'] as bool,
        gpsInterval: j['gpsInterval'] as int,
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.perBox,
    this.barcode,
    required this.wholesale,
    required this.retail,
  });

  final int id;
  final String name;
  final String category;
  final String unit;

  /// Штук в коробке.
  final int perBox;
  final String? barcode;

  /// Цены за штуку на день синхронизации, ₸.
  final int wholesale;
  final int retail;

  /// Цена по прайсу магазина: WHOLESALE — опт, RETAIL — розница.
  int priceFor(String priceKind) => priceKind == 'RETAIL' ? retail : wholesale;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as int,
        name: j['name'] as String,
        category: j['category'] as String,
        unit: j['unit'] as String,
        perBox: j['perBox'] as int,
        barcode: j['barcode'] as String?,
        wholesale: j['wholesale'] as int,
        retail: j['retail'] as int,
      );
}

class RouteInfo {
  const RouteInfo({required this.id, required this.name, this.region, required this.days, required this.outletIds});

  final int id;
  final String name;
  final String? region;

  /// Дни обхода: 1 — понедельник … 7 — воскресенье.
  final List<int> days;

  /// Магазины по порядку обхода.
  final List<int> outletIds;

  factory RouteInfo.fromJson(Map<String, dynamic> j) => RouteInfo(
        id: j['id'] as int,
        name: j['name'] as String,
        region: j['region'] as String?,
        days: [for (final d in j['days'] as List) d as int],
        outletIds: [for (final o in j['outlets'] as List) o as int],
      );
}

class Outlet {
  const Outlet({
    required this.id,
    required this.uuid,
    required this.name,
    this.legal,
    this.owner,
    this.phone,
    this.phone2,
    this.address,
    this.landmark,
    this.lat,
    this.lng,
    required this.priceKind,
    required this.creditLimit,
    required this.paymentDays,
    required this.status,
    required this.debt,
    required this.overdue,
    this.lastPaymentDate,
    required this.lastPaymentSum,
    this.mine = true,
  });

  final int id;
  final String uuid;
  final String name;

  /// ИП или ТОО.
  final String? legal;
  final String? owner;
  final String? phone;
  final String? phone2;
  final String? address;

  /// Ориентир — в сёлах вместо адреса.
  final String? landmark;
  final double? lat;
  final double? lng;

  /// WHOLESALE — опт, RETAIL — розница.
  final String priceKind;

  /// Лимит долга, ₸; 0 — без лимита.
  final int creditLimit;

  /// Отсрочка оплаты, дней.
  final int paymentDays;

  /// ACTIVE — работает, PENDING — на проверке у оператора.
  final String status;

  /// Долг и просрочка на день синхронизации, ₸ (минус — переплата).
  final int debt;
  final int overdue;
  final DateTime? lastPaymentDate;
  final int lastPaymentSum;

  /// Свой магазин (из маршрутов агента) — долги известны; чужой — без долгов.
  final bool mine;

  bool get pending => status == 'PENDING';
  bool get overLimit => creditLimit > 0 && debt > creditLimit;
  String get priceLabel => priceKind == 'RETAIL' ? 'Розница' : 'Опт';

  factory Outlet.fromJson(Map<String, dynamic> j) => Outlet(
        id: j['id'] as int,
        uuid: j['uuid'] as String,
        name: j['name'] as String,
        legal: j['legal'] as String?,
        owner: j['owner'] as String?,
        phone: j['phone'] as String?,
        phone2: j['phone2'] as String?,
        address: j['address'] as String?,
        landmark: j['landmark'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        priceKind: j['priceKind'] as String,
        creditLimit: j['creditLimit'] as int,
        paymentDays: j['paymentDays'] as int,
        status: j['status'] as String,
        debt: j['debt'] as int,
        overdue: j['overdue'] as int,
        lastPaymentDate: j['lastPaymentDate'] == null ? null : DateTime.parse(j['lastPaymentDate'] as String),
        lastPaymentSum: j['lastPaymentSum'] as int,
      );
}
