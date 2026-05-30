import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../../core/db/app_db.dart';
import '../pending_notification.dart';

class NotificationImportRepository {
  Future<Database> get _db async => await AppDb.instance;

  Future<void> _ensureAppsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS selected_notification_apps (
        packageName TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<void> _ensurePendingTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notifKey TEXT UNIQUE,
        packageName TEXT NOT NULL,
        title TEXT,
        text TEXT,
        postedAtMs INTEGER NOT NULL,
        rawJson TEXT,
        parsedAmount REAL,
        parsedIsIncome INTEGER,
        parsedMethod TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        createdAtMs INTEGER NOT NULL
      )
    ''');
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_pending_status ON pending_notifications(status)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_pending_posted ON pending_notifications(postedAtMs)",
    );
  }

  Future<void> setPackageEnabled(String packageName, bool enabled) async {
    final db = await _db;
    await _ensureAppsTable(db);

    await db.insert('selected_notification_apps', {
      'packageName': packageName,
      'enabled': enabled ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Set<String>> getEnabledPackages() async {
    final db = await _db;
    await _ensureAppsTable(db);

    final rows = await db.query(
      'selected_notification_apps',
      columns: ['packageName'],
      where: 'enabled = 1',
    );

    return rows
        .map((r) => (r['packageName'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Future<void> insertPending({
    required String notifKey,
    required String packageName,
    required String title,
    required String text,
    required int postedAtMs,
    String? rawJson,
    double? parsedAmount,
    bool? parsedIsIncome,
    String? parsedMethod,
  }) async {
    final db = await _db;
    await _ensurePendingTable(db);

    await db.insert(
      'pending_notifications',
      {
        'notifKey': notifKey,
        'packageName': packageName,
        'title': title,
        'text': text,
        'postedAtMs': postedAtMs,
        'rawJson': rawJson,
        'parsedAmount': parsedAmount,
        'parsedIsIncome': parsedIsIncome == null
            ? null
            : (parsedIsIncome ? 1 : 0),
        'parsedMethod': parsedMethod,
        'status': 'pending',
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore, // evita duplicados
    );
  }

  Future<int> countPending() async {
    final db = await _db;
    await _ensurePendingTable(db);

    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_notifications WHERE status = 'pending'",
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<PendingNotification>> getPending({int limit = 200}) async {
    final db = await _db;
    await _ensurePendingTable(db);

    final rows = await db.query(
      'pending_notifications',
      where: "status = 'pending'",
      orderBy: 'postedAtMs DESC, id DESC',
      limit: limit,
    );

    return rows.map(PendingNotification.fromMap).toList();
  }

  Future<void> markIgnored(int id) async {
    final db = await _db;
    await _ensurePendingTable(db);
    await db.update(
      'pending_notifications',
      {'status': 'ignored'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markImported(int id) async {
    final db = await _db;
    await _ensurePendingTable(db);
    await db.update(
      'pending_notifications',
      {'status': 'imported'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Compat: alguns patches antigos chamavam ignore(...)
  Future<void> ignore(int id) => markIgnored(id);
}
