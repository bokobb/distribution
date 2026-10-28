import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'track.dart';

/// Хранилище на телефоне: данные с сервера для работы без сети (по ключу, целиком JSON) и записи, которые ждут
/// отправки (журнал приложения и точки GPS).
abstract class LocalStore {
  Future<Map<String, dynamic>?> read(String key);

  Future<void> write(String key, Map<String, dynamic> json);

  Future<void> addEvent(TrackEvent e);

  /// Точка с тем же временем уже есть — не добавляется.
  Future<void> addPoint(TrackPoint p);

  /// Записи журнала с этого времени, по порядку — отправленные тоже (по ним видно, открыт ли рабочий день).
  Future<List<TrackEvent>> eventsSince(DateTime from);

  /// Самые старые неотправленные записи, не больше limit.
  Future<TrackBatch> unsent(int limit);

  /// Сервер принял — отметить отправленными; отправленное старше трёх дней стирается.
  Future<void> markSent(TrackBatch batch);

  Future<int> unsentCount();

  /// Стереть всё — при выходе: данные одного сотрудника не должны достаться следующему.
  Future<void> clear();
}

/// База SQLite на телефоне (distribution.db).
class SqliteStore implements LocalStore {
  SqliteStore._(this._db);

  final Database _db;

  static Future<SqliteStore> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'distribution.db'),
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('create table snapshot (key text primary key, json text not null, saved_at text not null)');
          await _createTrack(db);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await _createTrack(db);
        },
      ),
    );
    return SqliteStore._(db);
  }

  /// Версия 2: журнал приложения и точки GPS до отправки на сервер.
  static Future<void> _createTrack(Database db) async {
    await db.execute('create table journal (uuid text primary key, at text not null, kind text not null, note text, '
        'sent integer not null default 0)');
    await db.execute('create index journal_at on journal (at)');
    await db.execute('create table gps (at text primary key, lat real not null, lng real not null, accuracy integer, '
        'battery integer, sent integer not null default 0)');
  }

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    final rows = await _db.query('snapshot', columns: ['json'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String key, Map<String, dynamic> json) => _db.insert(
        'snapshot',
        {'key': key, 'json': jsonEncode(json), 'saved_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> addEvent(TrackEvent e) => _db.insert(
        'journal',
        {'uuid': e.uuid, 'at': e.at.toIso8601String(), 'kind': e.kind, 'note': e.note},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  @override
  Future<void> addPoint(TrackPoint pt) => _db.insert(
        'gps',
        {'at': pt.at.toIso8601String(), 'lat': pt.lat, 'lng': pt.lng, 'accuracy': pt.accuracy, 'battery': pt.battery},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  @override
  Future<List<TrackEvent>> eventsSince(DateTime from) async {
    final rows = await _db.query('journal', where: 'at >= ?', whereArgs: [from.toIso8601String()], orderBy: 'at');
    return rows.map(_event).toList();
  }

  @override
  Future<TrackBatch> unsent(int limit) async {
    final events = await _db.query('journal', where: 'sent = 0', orderBy: 'at', limit: limit);
    final points = await _db.query('gps', where: 'sent = 0', orderBy: 'at', limit: limit - events.length);
    return TrackBatch(
      events.map(_event).toList(),
      [
        for (final r in points)
          TrackPoint(
            at: DateTime.parse(r['at'] as String),
            lat: r['lat'] as double,
            lng: r['lng'] as double,
            accuracy: r['accuracy'] as int?,
            battery: r['battery'] as int?,
          ),
      ],
    );
  }

  @override
  Future<void> markSent(TrackBatch batch) => _db.transaction((tx) async {
        for (final e in batch.events) {
          await tx.update('journal', {'sent': 1}, where: 'uuid = ?', whereArgs: [e.uuid]);
        }
        for (final pt in batch.points) {
          await tx.update('gps', {'sent': 1}, where: 'at = ?', whereArgs: [pt.at.toIso8601String()]);
        }
        final old = DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
        await tx.delete('journal', where: 'sent = 1 and at < ?', whereArgs: [old]);
        await tx.delete('gps', where: 'sent = 1 and at < ?', whereArgs: [old]);
      });

  @override
  Future<int> unsentCount() async {
    final rows = await _db.rawQuery(
        'select (select count(*) from journal where sent = 0) + (select count(*) from gps where sent = 0) as n');
    return rows.first['n'] as int;
  }

  @override
  Future<void> clear() => _db.transaction((tx) async {
        await tx.delete('snapshot');
        await tx.delete('journal');
        await tx.delete('gps');
      });

  Future<void> close() => _db.close();

  static TrackEvent _event(Map<String, Object?> r) => TrackEvent(
        uuid: r['uuid'] as String,
        at: DateTime.parse(r['at'] as String),
        kind: r['kind'] as String,
        note: r['note'] as String?,
      );
}
