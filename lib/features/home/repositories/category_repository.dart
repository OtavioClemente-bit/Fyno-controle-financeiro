import 'package:sqflite/sqflite.dart';

import 'package:controle_financeiro/core/db/app_db.dart';
import 'package:controle_financeiro/features/home/models/category_item.dart';

class CategoryRepository {
  Future<Database> get _db async => AppDb.instance;

  Future<List<CategoryItem>> listAll() async {
    final db = await _db;
    final rows = await db.query(
      'categories',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(CategoryItem.fromMap).toList();
  }

  Future<int> create({required String name, required String iconKey}) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.insert('categories', {
      'name': name.trim(),
      'icon_key': iconKey,
      'created_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> update({
    required int id,
    required String name,
    required String iconKey,
  }) async {
    final db = await _db;
    return db.update(
      'categories',
      {'name': name.trim(), 'icon_key': iconKey},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<CategoryItem?> findByName(String name) async {
    final db = await _db;
    final rows = await db.query(
      'categories',
      where: 'name = ?',
      whereArgs: [name.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CategoryItem.fromMap(rows.first);
  }
}
