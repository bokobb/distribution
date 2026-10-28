import 'agent_data.dart';
import 'order.dart';

/// Данные экспедитора с сервера (/api/mobile/expeditor/data): незакрытые рейсы по сегодня и отгруженные на завтра,
/// точки по порядку — магазин с долгом и заказ с составом; товары с ценами на день синхронизации (для возврата
/// негодного); компания для накладной. Хранятся на телефоне целиком, обновляются целиком.
class ExpeditorData {
  ExpeditorData._(this.json, this.date, this.syncedAt, this.companyName, this.companyPhone, this.settings, this.products,
      this.trips);

  /// Как пришло с сервера — так и хранится на телефоне.
  final Map<String, dynamic> json;

  /// День на сервере, на который посчитаны цены и долги.
  final DateTime date;
  final DateTime syncedAt;
  final String? companyName;
  final String? companyPhone;
  final ExpeditorSettings settings;
  final List<Product> products;
  final List<TripInfo> trips;

  factory ExpeditorData.fromJson(Map<String, dynamic> json) {
    final company = json['company'] as Map<String, dynamic>?;
    return ExpeditorData._(
      json,
      DateTime.parse(json['date'] as String),
      DateTime.parse(json['syncedAt'] as String),
      company?['name'] as String?,
      company?['phone'] as String?,
      ExpeditorSettings.fromJson(json['settings'] as Map<String, dynamic>),
      [for (final p in json['products'] as List) Product.fromJson(p as Map<String, dynamic>)],
      [for (final t in json['trips'] as List) TripInfo.fromJson(t as Map<String, dynamic>)],
    );
  }

  /// Рейсы в работе: на день синхронизации и незакрытые прошлых дней.
  List<TripInfo> get current => trips.where((t) => !t.date.isAfter(date)).toList();

  /// Отгруженные на следующий день — посмотреть заранее.
  List<TripInfo> get upcoming => trips.where((t) => t.date.isAfter(date)).toList();
}

class ExpeditorSettings {
  const ExpeditorSettings({required this.acceptKaspi, required this.allowCredit, required this.gpsInterval});

  final bool acceptKaspi;
  final bool allowCredit;

  /// Как часто снимать точку GPS в рабочий день, минут.
  final int gpsInterval;

  factory ExpeditorSettings.fromJson(Map<String, dynamic> j) => ExpeditorSettings(
        acceptKaspi: j['acceptKaspi'] as bool,
        allowCredit: j['allowCredit'] as bool,
        gpsInterval: j['gpsInterval'] as int? ?? 5,
      );
}

class TripInfo {
  const TripInfo(
      {required this.id,
      required this.number,
      required this.date,
      required this.statusLabel,
      this.vehicle,
      required this.stops,
      this.cash = const TripCash()});

  final int id;
  final String number;
  final DateTime date;
  final String statusLabel;

  /// Номер машины.
  final String? vehicle;

  /// Точки по порядку объезда.
  final List<Stop> stops;

  /// Деньги и возвраты рейса на сервере.
  final TripCash cash;

  /// Сколько точек пройдено (выдано или отказ).
  int get done => stops.where((s) => s.order.done).length;

  factory TripInfo.fromJson(Map<String, dynamic> j) => TripInfo(
        id: j['id'] as int,
        number: j['number'] as String,
        date: DateTime.parse(j['date'] as String),
        statusLabel: j['statusLabel'] as String,
        vehicle: j['vehicle'] as String?,
        stops: [for (final s in j['stops'] as List) Stop.fromJson(s as Map<String, dynamic>)],
        cash: j['cash'] == null ? const TripCash() : TripCash.fromJson(j['cash'] as Map<String, dynamic>),
      );
}

/// Деньги и возвраты рейса на сервере — как их увидит касса: наличные и Kaspi — все оплаты (за заказы и в счёт
/// долгов), oldDebt — из них оплаты долгов; возвраты негодного — штук и на сколько уменьшили долги.
class TripCash {
  const TripCash({this.cash = 0, this.kaspi = 0, this.oldDebt = 0, this.returnsQty = 0, this.returnsTotal = 0});

  final int cash;
  final int kaspi;
  final int oldDebt;
  final int returnsQty;
  final int returnsTotal;

  factory TripCash.fromJson(Map<String, dynamic> j) => TripCash(
        cash: j['cash'] as int? ?? 0,
        kaspi: j['kaspi'] as int? ?? 0,
        oldDebt: j['oldDebt'] as int? ?? 0,
        returnsQty: j['returnsQty'] as int? ?? 0,
        returnsTotal: j['returnsTotal'] as int? ?? 0,
      );
}

/// Точка рейса: магазин (с долгом на день синхронизации) и его заказ.
class Stop {
  const Stop({required this.position, required this.outlet, required this.order});

  final int position;
  final Outlet outlet;
  final TripOrder order;

  factory Stop.fromJson(Map<String, dynamic> j) => Stop(
        position: j['position'] as int,
        outlet: Outlet.fromJson(j['outlet'] as Map<String, dynamic>),
        order: TripOrder.fromJson(j['order'] as Map<String, dynamic>),
      );
}

/// Заказ в рейсе: как оформил торговый, что уже выдано и оплачено.
class TripOrder {
  const TripOrder(
      {required this.id,
      required this.uuid,
      required this.number,
      this.agent,
      required this.deliveryDate,
      required this.payment,
      this.comment,
      required this.status,
      required this.statusLabel,
      required this.total,
      required this.paid,
      required this.lines});

  final int id;
  final String uuid;
  final String number;

  /// Торговый, который принял заказ.
  final String? agent;
  final DateTime deliveryDate;

  /// CASH, KASPI, CREDIT.
  final String payment;
  final String? comment;
  final String status;
  final String statusLabel;
  final int total;

  /// Сколько уже оплачено по заказу.
  final int paid;
  final List<TripLine> lines;

  String get paymentLabel => Order.paymentLabels[payment] ?? payment;

  /// Выдан целиком, частично или магазин отказался.
  bool get done => const {'DELIVERED', 'PARTIAL', 'REFUSED'}.contains(status);
  bool get refused => status == 'REFUSED';

  factory TripOrder.fromJson(Map<String, dynamic> j) => TripOrder(
        id: j['id'] as int,
        uuid: j['uuid'] as String,
        number: j['number'] as String,
        agent: j['agent'] as String?,
        deliveryDate: DateTime.parse(j['deliveryDate'] as String),
        payment: j['payment'] as String,
        comment: j['comment'] as String?,
        status: j['status'] as String,
        statusLabel: j['statusLabel'] as String,
        total: j['total'] as int,
        paid: j['paid'] as int? ?? 0,
        lines: [for (final l in j['lines'] as List) TripLine.fromJson(l as Map<String, dynamic>)],
      );
}

/// Строка заказа: price — за штуку со скидкой; delivered — сколько выдано, null — ещё не выдавали.
class TripLine {
  const TripLine(
      {required this.productId,
      required this.name,
      required this.unit,
      required this.perBox,
      required this.qty,
      required this.price,
      this.delivered});

  final int productId;
  final String name;
  final String unit;
  final int perBox;
  final int qty;
  final int price;
  final int? delivered;

  int get sum => qty * price;

  factory TripLine.fromJson(Map<String, dynamic> j) => TripLine(
        productId: j['productId'] as int,
        name: j['name'] as String,
        unit: j['unit'] as String? ?? 'шт',
        perBox: j['perBox'] as int? ?? 1,
        qty: j['qty'] as int,
        price: j['price'] as int,
        delivered: j['delivered'] as int?,
      );
}
