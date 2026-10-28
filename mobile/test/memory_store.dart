import 'package:distribution_mobile/data/local_store.dart';
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

  @override
  Future<Map<String, dynamic>?> read(String key) async => data[key];

  @override
  Future<void> write(String key, Map<String, dynamic> json) async => data[key] = json;

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
        done.where((v) => v.photo != null && !v.photoSent).length;
  }

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
  Future<void> clear() async {
    data.clear();
    events.clear();
    points.clear();
    sent.clear();
    visits.clear();
  }

  static List<Visit> _sorted(Iterable<Visit> vs) =>
      [for (final v in vs) v.copy()]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  List<String> kinds() => events.map((e) => e.kind).toList();
}
