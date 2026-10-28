import 'package:distribution_mobile/data/local_store.dart';
import 'package:distribution_mobile/data/track.dart';

/// Хранилище в памяти — вместо SQLite в тестах экранов и рабочего дня.
class MemoryStore implements LocalStore {
  final data = <String, Map<String, dynamic>>{};
  final events = <TrackEvent>[];
  final points = <TrackPoint>[];
  final sent = <Object>{};

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
  Future<int> unsentCount() async =>
      events.where((x) => !sent.contains(x.uuid)).length + points.where((x) => !sent.contains(x.at)).length;

  @override
  Future<void> clear() async {
    data.clear();
    events.clear();
    points.clear();
    sent.clear();
  }

  List<String> kinds() => events.map((e) => e.kind).toList();
}
