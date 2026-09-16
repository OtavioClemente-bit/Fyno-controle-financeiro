import 'package:sqflite/sqflite.dart';
import 'package:controle_financeiro/core/db/app_db.dart';

import '../pending_notification.dart';

class NotificationImportRepository {
  Future<Database> get _db async => AppDb.instance;

  // ------------------------------
  // Apps selecionados
  // ------------------------------
  Future<Set<String>> getEnabledPackages() async {
    final db = await _db;
    final rows = await db.query(
      'selected_notification_apps',
      columns: ['package_name'],
      where: 'enabled = 1',
    );
    return rows.map((r) => (r['package_name'] as String)).toSet();
  }

  Future<void> setPackageEnabled(String packageName, bool enabled) async {
    final db = await _db;
    // upsert simples: mantém package_name único.
    await db.insert('selected_notification_apps', {
      'package_name': packageName,
      'enabled': enabled ? 1 : 0,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setEnabledPackages(Set<String> packageNames) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('selected_notification_apps', {'enabled': 0});
      for (final packageName in packageNames) {
        await txn.insert(
          'selected_notification_apps',
          {
            'package_name': packageName,
            'enabled': 1,
            'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ------------------------------
  // Caixa de entrada (pending_notifications)
  // ------------------------------
  Future<int> countPending() async {
    final db = await _db;
    await activateDueReminders();
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_notifications WHERE status = 'pending'",
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countScheduledReminders() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_notifications WHERE status = 'snoozed'",
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<PendingNotification>> getPending() async {
    final db = await _db;
    await activateDueReminders();
    final rows = await db.query(
      'pending_notifications',
      where: "status IN ('pending', 'snoozed')",
      orderBy:
          "CASE WHEN status = 'pending' THEN 0 ELSE 1 END, "
          'COALESCE(reminder_at_ms, posted_at_ms) ASC, posted_at_ms DESC',
    );
    return rows.map((r) => PendingNotification.fromMap(r)).toList();
  }

  Future<void> ignore(int id) async {
    final db = await _db;
    await db.update(
      'pending_notifications',
      {'status': 'ignored', 'reminder_at_ms': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markImported(int id) async {
    final db = await _db;
    await db.update(
      'pending_notifications',
      {'status': 'imported', 'reminder_at_ms': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearPending() async {
    final db = await _db;
    // Mantém histórico, só marca como ignorado.
    await db.update('pending_notifications', {
      'status': 'ignored',
      'reminder_at_ms': null,
    }, where: "status IN ('pending', 'snoozed')");
  }

  Future<void> snooze(int id, DateTime reminderAt) async {
    final db = await _db;
    await db.update(
      'pending_notifications',
      {
        'status': 'snoozed',
        'reminder_at_ms': reminderAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> bringBackNow(int id) async {
    final db = await _db;
    await db.update(
      'pending_notifications',
      {'status': 'pending', 'reminder_at_ms': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> activateDueReminders() async {
    final db = await _db;
    await db.update(
      'pending_notifications',
      {'status': 'pending'},
      where: "status = 'snoozed' AND reminder_at_ms <= ?",
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> insertPending({
    required String notifKey,
    required String packageName,
    required String title,
    required String text,
    required int postedAtMs,
  }) async {
    final db = await _db;
    await db.insert('pending_notifications', {
      'notif_key': notifKey,
      'package_name': packageName,
      'title': title,
      'text': text,
      'posted_at_ms': postedAtMs,
      'parsed_amount': null,
      'parsed_is_income': null,
      'parsed_method': null,
      'suggested_category': null,
      'reminder_at_ms': null,
      'status': 'pending',
      'imported_tx_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> insertPendingMany(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'pending_notifications',
        r,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }
}
