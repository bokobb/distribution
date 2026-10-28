import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'debt_payment.dart';
import 'defect_return.dart';
import 'delivery.dart';
import 'new_outlet.dart';
import 'order.dart';
import 'track.dart';
import 'visit.dart';

/// Что на телефоне ждёт отправки и что сервер не принял — для экрана «Отправка».
class Pending {
  const Pending(
      {this.track = 0,
      this.visits = 0,
      this.photos = 0,
      this.orders = 0,
      this.outlets = 0,
      this.deliveries = 0,
      this.debtPayments = 0,
      this.returns = 0,
      this.rejectedVisits = const [],
      this.rejectedOrders = const [],
      this.rejectedOutlets = const [],
      this.rejectedDeliveries = const [],
      this.rejectedDebtPayments = const [],
      this.rejectedReturns = const []});

  /// Записи журнала и точки GPS.
  final int track;
  final int visits;

  /// Фото полки и фасада.
  final int photos;
  final int orders;

  /// Новые магазины.
  final int outlets;

  /// Выдачи экспедитора.
  final int deliveries;

  /// Оплаты старого долга.
  final int debtPayments;

  /// Возвраты негодного товара.
  final int returns;
  final List<Visit> rejectedVisits;
  final List<Order> rejectedOrders;
  final List<NewOutlet> rejectedOutlets;
  final List<Delivery> rejectedDeliveries;
  final List<DebtPayment> rejectedDebtPayments;
  final List<DefectReturn> rejectedReturns;

  int get total => track + visits + photos + orders + outlets + deliveries + debtPayments + returns;
}

/// Хранилище на телефоне: данные с сервера для работы без сети (по ключу, целиком JSON) и записи, которые ждут
/// отправки (журнал приложения, точки GPS, визиты, заказы).
abstract class LocalStore {
  Future<Map<String, dynamic>?> read(String key);

  Future<void> write(String key, Map<String, dynamic> json);

  Future<void> remove(String key);

  Future<void> addEvent(TrackEvent e);

  /// Точка с тем же временем уже есть — не добавляется.
  Future<void> addPoint(TrackPoint p);

  /// Записи журнала с этого времени, по порядку — отправленные тоже (по ним видно, открыт ли рабочий день).
  Future<List<TrackEvent>> eventsSince(DateTime from);

  /// Самые старые неотправленные записи, не больше limit.
  Future<TrackBatch> unsent(int limit);

  /// Сервер принял — отметить отправленными; отправленное старше трёх дней стирается.
  Future<void> markSent(TrackBatch batch);

  /// Сколько ждёт отправки: журнал, точки, законченные визиты и их фото, заказы.
  Future<int> unsentCount();

  /// Записать визит (новый или изменённый).
  Future<void> saveVisit(Visit v);

  Future<void> deleteVisit(String uuid);

  /// Визиты, начатые с этого времени, и незаконченный — каким бы днём он ни был.
  Future<List<Visit>> visitsSince(DateTime from);

  /// Законченные визиты, которые сервер ещё не получил сам или без фото; не принятые сервером — нет.
  Future<List<Visit>> visitsToSend();

  /// Стереть отправленные целиком визиты, начатые раньше before; вернуть их файлы фото — их тоже стереть.
  Future<List<String>> pruneVisits(DateTime before);

  /// Записать заказ (новый или с ответом сервера).
  Future<void> saveOrder(Order o);

  /// Заказы, созданные с этого времени.
  Future<List<Order>> ordersSince(DateTime from);

  /// Не отправленные и не отклонённые сервером, по порядку.
  Future<List<Order>> ordersToSend();

  /// Стереть отправленные заказы, созданные раньше before.
  Future<void> pruneOrders(DateTime before);

  Future<void> deleteOrder(String uuid);

  /// Записать новый магазин агента (новый или с отметкой отправки).
  Future<void> saveNewOutlet(NewOutlet o);

  /// Новые магазины на телефоне, по порядку: ждущие отправки, не принятые и недавно отправленные.
  Future<List<NewOutlet>> newOutlets();

  Future<void> deleteNewOutlet(String uuid);

  /// Стереть отправленные целиком (с фото) магазины, добавленные раньше before; вернуть их файлы фото.
  Future<List<String>> pruneNewOutlets(DateTime before);

  /// Записать выдачу (новую или с отметкой отправки / ответом сервера).
  Future<void> saveDelivery(Delivery d);

  /// Выдачи на телефоне — по времени.
  Future<List<Delivery>> deliveries();

  Future<void> deleteDelivery(String uuid);

  /// Стереть отправленные выдачи раньше before.
  Future<void> pruneDeliveries(DateTime before);

  /// Записать оплату долга (новую или с отметкой отправки / ответом сервера).
  Future<void> saveDebtPayment(DebtPayment p);

  /// Оплаты долга на телефоне — по времени.
  Future<List<DebtPayment>> debtPayments();

  Future<void> deleteDebtPayment(String uuid);

  /// Стереть отправленные оплаты долга раньше before.
  Future<void> pruneDebtPayments(DateTime before);

  /// Записать возврат негодного (новый или с отметкой отправки / ответом сервера).
  Future<void> saveReturn(DefectReturn r);

  /// Возвраты на телефоне — по времени.
  Future<List<DefectReturn>> returns();

  Future<void> deleteReturn(String uuid);

  /// Стереть отправленные возвраты раньше before.
  Future<void> pruneReturns(DateTime before);

  Future<Pending> pending();

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
        version: 8,
        onCreate: (db, version) async {
          await db.execute('create table snapshot (key text primary key, json text not null, saved_at text not null)');
          await _createTrack(db);
          await _createVisits(db);
          await _createOrders(db);
          await _createNewOutlets(db);
          await _createDeliveries(db);
          await _createDebtPayments(db);
          await _createReturns(db);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await _createTrack(db);
          if (from < 3) await _createVisits(db);
          if (from < 4) await _createOrders(db);
          if (from < 5) await _createNewOutlets(db);
          if (from < 6) await _createDeliveries(db);
          if (from < 7) await _createDebtPayments(db);
          if (from < 8) await _createReturns(db);
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

  /// Версия 3: визиты в магазины до отправки на сервер.
  static Future<void> _createVisits(Database db) async {
    await db.execute('create table visits (uuid text primary key, outlet_id integer not null, route_id integer, '
        'started_at text not null, finished_at text, lat real, lng real, accuracy integer, distance integer, '
        'result text, reason text, photo text, sent integer not null default 0, photo_sent integer not null default 0, '
        'error text)');
    await db.execute('create index visits_started on visits (started_at)');
  }

  /// Версия 4: заказы до отправки и с ответом сервера (номер, статус).
  static Future<void> _createOrders(Database db) async {
    await db.execute('create table orders (uuid text primary key, visit_uuid text, outlet_id integer not null, '
        'created_at text not null, delivery_date text not null, payment text not null, comment text, '
        'items text not null, total integer not null, sent integer not null default 0, error text, number text, '
        'status text, status_label text, note text)');
    await db.execute('create index orders_created on orders (created_at)');
  }

  /// Версия 5: новые магазины агента до отправки; поля — одной строкой JSON, отметки отправки — отдельно.
  static Future<void> _createNewOutlets(Database db) async {
    await db.execute('create table new_outlets (uuid text primary key, created_at text not null, json text not null, '
        'photo text, sent integer not null default 0, photo_sent integer not null default 0, error text)');
  }

  /// Версия 6: выдачи экспедитора до отправки и с ответом сервера; поля — одной строкой JSON.
  static Future<void> _createDeliveries(Database db) async {
    await db.execute('create table deliveries (uuid text primary key, order_id integer not null, '
        'delivered_at text not null, json text not null, sent integer not null default 0, error text)');
  }

  /// Версия 7: оплаты старого долга до отправки и с ответом сервера; поля — одной строкой JSON.
  static Future<void> _createDebtPayments(Database db) async {
    await db.execute('create table debt_payments (uuid text primary key, paid_at text not null, json text not null, '
        'sent integer not null default 0, error text)');
  }

  /// Версия 8: возвраты негодного товара до отправки и с ответом сервера; поля — одной строкой JSON.
  static Future<void> _createReturns(Database db) async {
    await db.execute('create table defect_returns (uuid text primary key, returned_at text not null, json text not null, '
        'sent integer not null default 0, error text)');
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
  Future<void> remove(String key) => _db.delete('snapshot', where: 'key = ?', whereArgs: [key]);

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
    final rows = await _db.rawQuery('select (select count(*) from journal where sent = 0) '
        '+ (select count(*) from gps where sent = 0) '
        '+ (select count(*) from visits where finished_at is not null and error is null and sent = 0) '
        '+ (select count(*) from visits where finished_at is not null and error is null and photo is not null '
        'and photo_sent = 0) '
        '+ (select count(*) from orders where sent = 0 and error is null) '
        '+ (select count(*) from new_outlets where error is null and sent = 0) '
        '+ (select count(*) from new_outlets where error is null and photo is not null and photo_sent = 0) '
        '+ (select count(*) from deliveries where sent = 0 and error is null) '
        '+ (select count(*) from debt_payments where sent = 0 and error is null) '
        '+ (select count(*) from defect_returns where sent = 0 and error is null) as n');
    return rows.first['n'] as int;
  }

  @override
  Future<void> saveVisit(Visit v) => _db.insert(
        'visits',
        {
          'uuid': v.uuid,
          'outlet_id': v.outletId,
          'route_id': v.routeId,
          'started_at': v.startedAt.toIso8601String(),
          'finished_at': v.finishedAt?.toIso8601String(),
          'lat': v.lat,
          'lng': v.lng,
          'accuracy': v.accuracy,
          'distance': v.distance,
          'result': v.result,
          'reason': v.reason,
          'photo': v.photo,
          'sent': v.sent ? 1 : 0,
          'photo_sent': v.photoSent ? 1 : 0,
          'error': v.error,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> deleteVisit(String uuid) => _db.delete('visits', where: 'uuid = ?', whereArgs: [uuid]);

  @override
  Future<List<Visit>> visitsSince(DateTime from) async {
    final rows = await _db.query('visits',
        where: 'started_at >= ? or finished_at is null', whereArgs: [from.toIso8601String()], orderBy: 'started_at');
    return rows.map(_visit).toList();
  }

  @override
  Future<List<Visit>> visitsToSend() async {
    final rows = await _db.query('visits',
        where: 'finished_at is not null and error is null and (sent = 0 or photo is not null and photo_sent = 0)',
        orderBy: 'started_at');
    return rows.map(_visit).toList();
  }

  @override
  Future<List<String>> pruneVisits(DateTime before) => _db.transaction((tx) async {
        const done = 'sent = 1 and (photo is null or photo_sent = 1) and started_at < ?';
        final args = [before.toIso8601String()];
        final rows = await tx.query('visits', columns: ['photo'], where: '$done and photo is not null', whereArgs: args);
        await tx.delete('visits', where: done, whereArgs: args);
        return [for (final r in rows) r['photo'] as String];
      });

  @override
  Future<void> saveOrder(Order o) => _db.insert(
        'orders',
        {
          'uuid': o.uuid,
          'visit_uuid': o.visitUuid,
          'outlet_id': o.outletId,
          'created_at': o.createdAt.toIso8601String(),
          'delivery_date': o.deliveryDate.toIso8601String(),
          'payment': o.payment,
          'comment': o.comment,
          'items': o.itemsJson(),
          'total': o.total,
          'sent': o.sent ? 1 : 0,
          'error': o.error,
          'number': o.number,
          'status': o.status,
          'status_label': o.statusLabel,
          'note': o.note,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<List<Order>> ordersSince(DateTime from) async {
    final rows =
        await _db.query('orders', where: 'created_at >= ?', whereArgs: [from.toIso8601String()], orderBy: 'created_at');
    return rows.map(_order).toList();
  }

  @override
  Future<List<Order>> ordersToSend() async {
    final rows = await _db.query('orders', where: 'sent = 0 and error is null', orderBy: 'created_at');
    return rows.map(_order).toList();
  }

  @override
  Future<void> pruneOrders(DateTime before) =>
      _db.delete('orders', where: 'sent = 1 and created_at < ?', whereArgs: [before.toIso8601String()]);

  @override
  Future<void> deleteOrder(String uuid) => _db.delete('orders', where: 'uuid = ?', whereArgs: [uuid]);

  @override
  Future<void> saveNewOutlet(NewOutlet o) => _db.insert(
        'new_outlets',
        {
          'uuid': o.uuid,
          'created_at': o.createdAt.toIso8601String(),
          'json': o.encode(),
          'photo': o.photo,
          'sent': o.sent ? 1 : 0,
          'photo_sent': o.photoSent ? 1 : 0,
          'error': o.error,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<List<NewOutlet>> newOutlets() async =>
      (await _db.query('new_outlets', columns: ['json'], orderBy: 'created_at'))
          .map((r) => NewOutlet.decode(r['json'] as String))
          .toList();

  @override
  Future<void> deleteNewOutlet(String uuid) => _db.delete('new_outlets', where: 'uuid = ?', whereArgs: [uuid]);

  @override
  Future<List<String>> pruneNewOutlets(DateTime before) => _db.transaction((tx) async {
        const done = 'sent = 1 and (photo is null or photo_sent = 1) and created_at < ?';
        final args = [before.toIso8601String()];
        final rows = await tx.query('new_outlets', columns: ['photo'], where: '$done and photo is not null', whereArgs: args);
        await tx.delete('new_outlets', where: done, whereArgs: args);
        return [for (final r in rows) r['photo'] as String];
      });

  @override
  Future<void> saveDelivery(Delivery d) => _db.insert(
        'deliveries',
        {
          'uuid': d.uuid,
          'order_id': d.orderId,
          'delivered_at': d.deliveredAt.toIso8601String(),
          'json': d.encode(),
          'sent': d.sent ? 1 : 0,
          'error': d.error,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<List<Delivery>> deliveries() async =>
      (await _db.query('deliveries', columns: ['json'], orderBy: 'delivered_at'))
          .map((r) => Delivery.decode(r['json'] as String))
          .toList();

  @override
  Future<void> deleteDelivery(String uuid) => _db.delete('deliveries', where: 'uuid = ?', whereArgs: [uuid]);

  @override
  Future<void> pruneDeliveries(DateTime before) =>
      _db.delete('deliveries', where: 'sent = 1 and delivered_at < ?', whereArgs: [before.toIso8601String()]);

  @override
  Future<void> saveDebtPayment(DebtPayment p) => _db.insert(
        'debt_payments',
        {'uuid': p.uuid, 'paid_at': p.paidAt.toIso8601String(), 'json': p.encode(), 'sent': p.sent ? 1 : 0, 'error': p.error},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<List<DebtPayment>> debtPayments() async =>
      (await _db.query('debt_payments', columns: ['json'], orderBy: 'paid_at'))
          .map((r) => DebtPayment.decode(r['json'] as String))
          .toList();

  @override
  Future<void> deleteDebtPayment(String uuid) => _db.delete('debt_payments', where: 'uuid = ?', whereArgs: [uuid]);

  @override
  Future<void> pruneDebtPayments(DateTime before) =>
      _db.delete('debt_payments', where: 'sent = 1 and paid_at < ?', whereArgs: [before.toIso8601String()]);

  @override
  Future<void> saveReturn(DefectReturn r) => _db.insert(
        'defect_returns',
        {
          'uuid': r.uuid,
          'returned_at': r.returnedAt.toIso8601String(),
          'json': r.encode(),
          'sent': r.sent ? 1 : 0,
          'error': r.error,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<List<DefectReturn>> returns() async =>
      (await _db.query('defect_returns', columns: ['json'], orderBy: 'returned_at'))
          .map((r) => DefectReturn.decode(r['json'] as String))
          .toList();

  @override
  Future<void> deleteReturn(String uuid) => _db.delete('defect_returns', where: 'uuid = ?', whereArgs: [uuid]);

  @override
  Future<void> pruneReturns(DateTime before) =>
      _db.delete('defect_returns', where: 'sent = 1 and returned_at < ?', whereArgs: [before.toIso8601String()]);

  @override
  Future<Pending> pending() async {
    Future<int> count(String sql) async => (await _db.rawQuery(sql)).first['n'] as int;
    return Pending(
      track: await count('select (select count(*) from journal where sent = 0) '
          '+ (select count(*) from gps where sent = 0) as n'),
      visits: await count('select count(*) as n from visits where finished_at is not null and error is null and sent = 0'),
      photos: await count('select (select count(*) from visits where finished_at is not null and error is null '
          'and photo is not null and photo_sent = 0) '
          '+ (select count(*) from new_outlets where error is null and photo is not null and photo_sent = 0) as n'),
      orders: await count('select count(*) as n from orders where sent = 0 and error is null'),
      outlets: await count('select count(*) as n from new_outlets where error is null and sent = 0'),
      deliveries: await count('select count(*) as n from deliveries where sent = 0 and error is null'),
      debtPayments: await count('select count(*) as n from debt_payments where sent = 0 and error is null'),
      returns: await count('select count(*) as n from defect_returns where sent = 0 and error is null'),
      rejectedVisits: (await _db.query('visits', where: 'error is not null', orderBy: 'started_at')).map(_visit).toList(),
      rejectedOrders: (await _db.query('orders', where: 'error is not null', orderBy: 'created_at')).map(_order).toList(),
      rejectedOutlets: (await _db.query('new_outlets', columns: ['json'], where: 'error is not null', orderBy: 'created_at'))
          .map((r) => NewOutlet.decode(r['json'] as String))
          .toList(),
      rejectedDeliveries: (await _db.query('deliveries', columns: ['json'], where: 'error is not null', orderBy: 'delivered_at'))
          .map((r) => Delivery.decode(r['json'] as String))
          .toList(),
      rejectedDebtPayments: (await _db.query('debt_payments', columns: ['json'], where: 'error is not null', orderBy: 'paid_at'))
          .map((r) => DebtPayment.decode(r['json'] as String))
          .toList(),
      rejectedReturns: (await _db.query('defect_returns', columns: ['json'], where: 'error is not null', orderBy: 'returned_at'))
          .map((r) => DefectReturn.decode(r['json'] as String))
          .toList(),
    );
  }

  @override
  Future<void> clear() => _db.transaction((tx) async {
        await tx.delete('snapshot');
        await tx.delete('journal');
        await tx.delete('gps');
        await tx.delete('visits');
        await tx.delete('orders');
        await tx.delete('new_outlets');
        await tx.delete('deliveries');
        await tx.delete('debt_payments');
        await tx.delete('defect_returns');
      });

  Future<void> close() => _db.close();

  static Order _order(Map<String, Object?> r) => Order(
        uuid: r['uuid'] as String,
        visitUuid: r['visit_uuid'] as String?,
        outletId: r['outlet_id'] as int,
        createdAt: DateTime.parse(r['created_at'] as String),
        deliveryDate: DateTime.parse(r['delivery_date'] as String),
        payment: r['payment'] as String,
        comment: r['comment'] as String?,
        items: Order.parseItems(r['items'] as String),
        total: r['total'] as int,
        sent: r['sent'] == 1,
        error: r['error'] as String?,
        number: r['number'] as String?,
        status: r['status'] as String?,
        statusLabel: r['status_label'] as String?,
        note: r['note'] as String?,
      );

  static Visit _visit(Map<String, Object?> r) => Visit(
        uuid: r['uuid'] as String,
        outletId: r['outlet_id'] as int,
        routeId: r['route_id'] as int?,
        startedAt: DateTime.parse(r['started_at'] as String),
        finishedAt: r['finished_at'] == null ? null : DateTime.parse(r['finished_at'] as String),
        lat: r['lat'] as double?,
        lng: r['lng'] as double?,
        accuracy: r['accuracy'] as int?,
        distance: r['distance'] as int?,
        result: r['result'] as String?,
        reason: r['reason'] as String?,
        photo: r['photo'] as String?,
        sent: r['sent'] == 1,
        photoSent: r['photo_sent'] == 1,
        error: r['error'] as String?,
      );

  static TrackEvent _event(Map<String, Object?> r) => TrackEvent(
        uuid: r['uuid'] as String,
        at: DateTime.parse(r['at'] as String),
        kind: r['kind'] as String,
        note: r['note'] as String?,
      );
}
