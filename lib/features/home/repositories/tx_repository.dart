import '../../../core/db/app_db.dart';
import '../models/tx_item.dart';

class TxRepository {
  /// Insere uma nova transação no banco
  Future<int> insert(TxItem tx) async {
    final db = await AppDb.instance;
    return db.insert('transactions', tx.toMap());
  }

  /// Retorna todas as transações (mais recentes primeiro)
  Future<List<TxItem>> getAll() async {
    final db = await AppDb.instance;

    final rows = await db.query(
      'transactions',
      orderBy: 'date_ms DESC, id DESC',
    );

    return rows.map(TxItem.fromMap).toList();
  }

  /// Atualiza uma transação existente
  Future<int> update(TxItem tx) async {
    if (tx.id == null) return 0;

    final db = await AppDb.instance;

    return db.update(
      'transactions',
      tx.toMap(),
      where: 'id = ?',
      whereArgs: [tx.id],
    );
  }

  /// Remove uma transação pelo ID
  Future<int> delete(int id) async {
    final db = await AppDb.instance;

    return db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }
}
