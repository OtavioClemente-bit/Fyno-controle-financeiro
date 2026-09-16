import 'package:controle_financeiro/core/db/app_db.dart';
import 'receipt_item_draft.dart';
import 'normalize_product.dart';

class ReceiptItemsRepository {
  static Future<void> insertMany({
    required int txId,
    required DateTime date,
    required List<ReceiptItemDraft> items,
    String? market,
  }) async {
    if (items.isEmpty) return;
    final db = await AppDb.instance;

    final batch = db.batch();
    for (final it in items) {
      final display = it.name.trim();
      final raw = it.originalName.trim().isEmpty
          ? display
          : it.originalName.trim();
      if (display.isEmpty) continue;
      batch.insert('receipt_items', {
        'tx_id': txId,
        'date_ms': date.millisecondsSinceEpoch,
        'raw_name': raw,
        'display_name': display,
        'norm_name': normalizeProductName(display),
        'price': it.price,
        'qty': it.qty,
        'unit': it.unit,
        'market': market,
        'line_total': it.effectiveLineTotal,
        'price_source': it.priceSource.name,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Lista produtos distintos (para autocomplete).
  static Future<List<Map<String, Object?>>> searchProducts(String query) async {
    final q = normalizeProductName(query);
    final db = await AppDb.instance;

    // Busca em norm_name para ser robusto (sem acento).
    final rows = await db.rawQuery(
      '''
      SELECT norm_name,
             MIN(COALESCE(display_name, raw_name)) AS display_name,
             COUNT(*) AS count
      FROM receipt_items
      WHERE norm_name LIKE ?
      GROUP BY norm_name
      ORDER BY display_name COLLATE NOCASE
      LIMIT 50
    ''',
      ['%$q%'],
    );

    return rows;
  }

  /// Histórico de preços por produto (norm_name).
  static Future<List<Map<String, Object?>>> getHistoryByNormName(
    String normName,
  ) async {
    final db = await AppDb.instance;
    return db.rawQuery(
      '''
      SELECT id, tx_id, date_ms, raw_name,
             COALESCE(display_name, raw_name) AS display_name,
             price, qty, unit, market, line_total, price_source
      FROM receipt_items
      WHERE norm_name = ?
      ORDER BY date_ms DESC, id DESC
      LIMIT 500
    ''',
      [normName],
    );
  }
}
