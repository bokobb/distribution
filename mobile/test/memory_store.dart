import 'package:distribution_mobile/data/debt_payment.dart';
import 'package:distribution_mobile/data/defect_return.dart';
import 'package:distribution_mobile/data/delivery.dart';
import 'package:distribution_mobile/data/local_store.dart';
import 'package:distribution_mobile/data/new_outlet.dart';
import 'package:distribution_mobile/data/order.dart';
import 'package:distribution_mobile/data/track.dart';
import 'package:distribution_mobile/data/visit.dart';

/// Хранилище в памяти — вместо SQLite в тестах экранов и рабочего дня.
class MemoryStore implements LocalStore {
  final data = <String, Map<String, dynamic>>{};
  final events = <TrackEvent>[];
  final points = <TrackPoint>[];
  final sent = <Object>{};

  /// Визиты по uuid — копиями, как в базе: изменение без saveVisit сюда не попадёт.
  final visits = <String, Visit>{};
  final orders = <String, Order>{};
  final newOutletsByUuid = <String, NewOutlet>{};
  final deliveriesByUuid = <String, Delivery>{};
  final debtPaymentsByUuid = <String, DebtPayment>{};
  final returnsByUuid = <String, DefectReturn>{};

  @override
  Future<Map<String, dynamic>?> read(String key) async => data[key];

  @override
  Future<void> write(String key, Map<String, dynamic> json) async => data[key] = json;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<void> addEvent(TrackEvent e) async => events.add(e);

  @override
  Future<void> addPoint(TrackPoint p) async {
    if (points.every((x) => x.at != p.at)) points.add(p);
  }

  @override
  Future<List<TrackEvent>> eventsSince(DateTime from) async =>
      (events.where((e) => !e.at.isBefore(from)).toList()..sort((a, b) => a.at.compareTo(b.at)));

  @override
  Future<TrackBatch> unsent(int limit) async {
    final e = events.where((x) => !sent.contains(x.uuid)).take(limit).toList();
    final p = points.where((x) => !sent.contains(x.at)).take(limit - e.length).toList();
    return TrackBatch(e, p);
  }

  @override
  Future<void> markSent(TrackBatch batch) async {
    sent.addAll(batch.events.map((e) => e.uuid));
    sent.addAll(batch.points.map((p) => p.at));
  }

  @override
  Future<int> unsentCount() async {
    final done = visits.values.where((v) => !v.open && v.error == null);
    return events.where((x) => !sent.contains(x.uuid)).length +
        points.where((x) => !sent.contains(x.at)).length +
        done.where((v) => !v.sent).length +
        done.where((v) => v.photo != null && !v.photoSent).length +
        orders.values.where((o) => !o.sent && o.error == null).length +
        newOutletsByUuid.values.where((o) => o.error == null && !o.sent).length +
        newOutletsByUuid.values.where((o) => o.error == null && o.photo != null && !o.photoSent).length +
        deliveriesByUuid.values.where((d) => !d.uploaded && d.error == null).length +
        debtPaymentsByUuid.values.where((p) => !p.sent && p.error == null).length +
        returnsByUuid.values.where((r) => !r.sent && r.error == null).length;
  }

  @override
  Future<void> saveReturn(DefectReturn r) async => returnsByUuid[r.uuid] = r.copy();

  @override
  Future<List<DefectReturn>> returns() async =>
      [for (final r in returnsByUuid.values) r.copy()]..sort((a, b) => a.returnedAt.compareTo(b.returnedAt));

  @override
  Future<void> deleteReturn(String uuid) async => returnsByUuid.remove(uuid);

  @override
  Future<void> pruneReturns(DateTime before) async =>
      returnsByUuid.removeWhere((_, r) => r.sent && r.returnedAt.isBefore(before));

  @override
  Future<void> saveDebtPayment(DebtPayment p) async => debtPaymentsByUuid[p.uuid] = p.copy();

  @override
  Future<List<DebtPayment>> debtPayments() async =>
      [for (final p in debtPaymentsByUuid.values) p.copy()]..sort((a, b) => a.paidAt.compareTo(b.paidAt));

  @override
  Future<void> deleteDebtPayment(String uuid) async => debtPaymentsByUuid.remove(uuid);

  @override
  Future<void> pruneDebtPayments(DateTime before) async =>
      debtPaymentsByUuid.removeWhere((_, p) => p.sent && p.paidAt.isBefore(before));

  @override
  Future<void> saveDelivery(Delivery d) async => deliveriesByUuid[d.uuid] = d.copy();

  @override
  Future<List<Delivery>> deliveries() async =>
      [for (final d in deliveriesByUuid.values) d.copy()]..sort((a, b) => a.deliveredAt.compareTo(b.deliveredAt));

  @override
  Future<void> deleteDelivery(String uuid) async => deliveriesByUuid.remove(uuid);

  @override
  Future<void> pruneDeliveries(DateTime before) async =>
      deliveriesByUuid.removeWhere((_, d) => d.uploaded && d.deliveredAt.isBefore(before));

  @override
  Future<void> saveNewOutlet(NewOutlet o) async => newOutletsByUuid[o.uuid] = o.copy();

  @override
  Future<List<NewOutlet>> newOutlets() async =>
      [for (final o in newOutletsByUuid.values) o.copy()]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> deleteNewOutlet(String uuid) async => newOutletsByUuid.remove(uuid);

  @override
  Future<List<String>> pruneNewOutlets(DateTime before) async {
    final old = newOutletsByUuid.values
        .where((o) => o.sent && (o.photo == null || o.photoSent) && o.createdAt.isBefore(before))
        .toList();
    for (final o in old) {
      newOutletsByUuid.remove(o.uuid);
    }
    return [for (final o in old) ?o.photo];
  }

  @override
  Future<void> saveOrder(Order o) async => orders[o.uuid] = o.copy();

  @override
  Future<List<Order>> ordersSince(DateTime from) async =>
      [for (final o in orders.values) if (!o.createdAt.isBefore(from)) o.copy()]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<List<Order>> ordersToSend() async =>
      [for (final o in orders.values) if (!o.sent && o.error == null) o.copy()]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> pruneOrders(DateTime before) async =>
      orders.removeWhere((_, o) => o.sent && o.createdAt.isBefore(before));

  @override
  Future<void> saveVisit(Visit v) async => visits[v.uuid] = v.copy();

  @override
  Future<void> deleteVisit(String uuid) async => visits.remove(uuid);

  @override
  Future<List<Visit>> visitsSince(DateTime from) async =>
      _sorted(visits.values.where((v) => !v.startedAt.isBefore(from) || v.open));

  @override
  Future<List<Visit>> visitsToSend() async => _sorted(visits.values
      .where((v) => !v.open && v.error == null && (!v.sent || v.photo != null && !v.photoSent)));

  @override
  Future<List<String>> pruneVisits(DateTime before) async {
    final old = visits.values
        .where((v) => v.sent && (v.photo == null || v.photoSent) && v.startedAt.isBefore(before))
        .toList();
    for (final v in old) {
      visits.remove(v.uuid);
    }
    return [for (final v in old) ?v.photo];
  }

  @override
  Future<void> deleteOrder(String uuid) async => orders.remove(uuid);

  @override
  Future<Pending> pending() async {
    final done = visits.values.where((v) => !v.open && v.error == null);
    return Pending(
      track: events.where((x) => !sent.contains(x.uuid)).length + points.where((x) => !sent.contains(x.at)).length,
      visits: done.where((v) => !v.sent).length,
      photos: done.where((v) => v.photo != null && !v.photoSent).length +
          newOutletsByUuid.values.where((o) => o.error == null && o.photo != null && !o.photoSent).length,
      orders: orders.values.where((o) => !o.sent && o.error == null).length,
      outlets: newOutletsByUuid.values.where((o) => o.error == null && !o.sent).length,
      deliveries: deliveriesByUuid.values.where((d) => !d.uploaded && d.error == null).length,
      debtPayments: debtPaymentsByUuid.values.where((p) => !p.sent && p.error == null).length,
      returns: returnsByUuid.values.where((r) => !r.sent && r.error == null).length,
      rejectedVisits: _sorted(visits.values.where((v) => v.error != null)),
      rejectedOrders: [for (final o in orders.values) if (o.error != null) o.copy()],
      rejectedOutlets: [for (final o in newOutletsByUuid.values) if (o.error != null) o.copy()],
      rejectedDeliveries: [for (final d in deliveriesByUuid.values) if (d.error != null) d.copy()],
      rejectedDebtPayments: [for (final p in debtPaymentsByUuid.values) if (p.error != null) p.copy()],
      rejectedReturns: [for (final r in returnsByUuid.values) if (r.error != null) r.copy()],
    );
  }

  @override
  Future<void> clear() async {
    data.clear();
    events.clear();
    points.clear();
    sent.clear();
    visits.clear();
    orders.clear();
    newOutletsByUuid.clear();
    deliveriesByUuid.clear();
    debtPaymentsByUuid.clear();
    returnsByUuid.clear();
  }

  static List<Visit> _sorted(Iterable<Visit> vs) =>
      [for (final v in vs) v.copy()]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  List<String> kinds() => events.map((e) => e.kind).toList();
}
