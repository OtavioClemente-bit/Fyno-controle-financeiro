import '../../core/db/app_db.dart';
import 'package:sqflite/sqflite.dart';

class MonthlyBudget {
  const MonthlyBudget({
    this.id,
    required this.category,
    required this.amount,
    this.warningPercent = 80,
    this.active = true,
  });

  final int? id;
  final String category;
  final double amount;
  final int warningPercent;
  final bool active;

  factory MonthlyBudget.fromMap(Map<String, Object?> map) => MonthlyBudget(
    id: (map['id'] as num?)?.toInt(),
    category: map['category'] as String,
    amount: (map['amount'] as num).toDouble(),
    warningPercent: (map['warning_percent'] as num?)?.toInt() ?? 80,
    active: (map['active'] as num?)?.toInt() != 0,
  );
}

class BudgetProgress {
  const BudgetProgress({required this.budget, required this.spent});
  final MonthlyBudget budget;
  final double spent;
  double get remaining => budget.amount - spent;
  double get ratio => budget.amount <= 0 ? 0 : spent / budget.amount;
  bool get exceeded => spent > budget.amount;
}

class BudgetRepository {
  Future<List<BudgetProgress>> getProgress(DateTime month) async {
    final db = await AppDb.instance;
    final budgets = (await db.query(
      'monthly_budgets',
      where: 'active = 1',
      orderBy: 'LOWER(category)',
    )).map(MonthlyBudget.fromMap).toList();
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final rows = await db.rawQuery(
      '''SELECT LOWER(TRIM(category)) AS category_key, SUM(amount) AS spent
         FROM transactions
         WHERE is_income = 0
           AND LOWER(TRIM(payment_method)) != 'pagamento da fatura'
           AND date_ms >= ? AND date_ms < ?
         GROUP BY LOWER(TRIM(category))''',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    final spentByCategory = <String, double>{
      for (final row in rows)
        '${row['category_key']}': (row['spent'] as num?)?.toDouble() ?? 0,
    };
    return [
      for (final budget in budgets)
        BudgetProgress(
          budget: budget,
          spent: spentByCategory[budget.category.trim().toLowerCase()] ?? 0,
        ),
    ];
  }

  Future<void> save(MonthlyBudget budget) async {
    final db = await AppDb.instance;
    final values = <String, Object?>{
      'category': budget.category.trim(),
      'amount': budget.amount,
      'warning_percent': budget.warningPercent.clamp(50, 100),
      'active': budget.active ? 1 : 0,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (budget.id == null) {
      await db.insert(
        'monthly_budgets',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      values.remove('created_at_ms');
      await db.update(
        'monthly_budgets',
        values,
        where: 'id = ?',
        whereArgs: [budget.id],
      );
    }
  }

  Future<void> archive(int id) async {
    final db = await AppDb.instance;
    await db.update(
      'monthly_budgets',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
