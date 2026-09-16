import 'package:sqflite/sqflite.dart';

import '../../../../../core/db/app_db.dart';
import '../../../models/tx_item.dart';
import '../smart_transaction_rule.dart';

class SmartRulesRepository {
  Future<List<SmartTransactionRule>> getAll() async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'transaction_learning_rules',
      orderBy: 'updated_at_ms DESC',
    );
    return rows.map(SmartTransactionRule.fromMap).toList(growable: false);
  }

  Future<SmartTransactionRule?> findFor(String title, String text) async {
    final identity = MerchantIdentity.extract(title, text);
    if (identity == null) return null;
    final db = await AppDb.instance;
    final rows = await db.query(
      'transaction_learning_rules',
      where: 'merchant_key = ?',
      whereArgs: [identity.key],
      limit: 1,
    );
    return rows.isEmpty ? null : SmartTransactionRule.fromMap(rows.first);
  }

  Future<void> learn({
    required String notificationTitle,
    required String notificationText,
    required TxItem transaction,
  }) async {
    final identity = MerchantIdentity.extract(
      notificationTitle,
      notificationText,
    );
    if (identity == null) return;
    final db = await AppDb.instance;
    final existing = await db.query(
      'transaction_learning_rules',
      columns: const ['use_count'],
      where: 'merchant_key = ?',
      whereArgs: [identity.key],
      limit: 1,
    );
    final count = existing.isEmpty
        ? 1
        : ((existing.first['use_count'] as num?)?.toInt() ?? 0) + 1;
    await db.insert('transaction_learning_rules', {
      'merchant_key': identity.key,
      'merchant_name': identity.name,
      'title': transaction.title,
      'category': transaction.category,
      'is_income': transaction.isIncome ? 1 : 0,
      'payment_method': transaction.paymentMethod,
      'use_count': count,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(int id) async {
    final db = await AppDb.instance;
    await db.delete(
      'transaction_learning_rules',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
