import '../../core/db/app_db.dart';

class SavingsGoal {
  const SavingsGoal({
    this.id,
    required this.name,
    required this.targetAmount,
    required this.savedAmount,
    this.deadline,
    required this.iconKey,
    required this.colorValue,
    this.completed = false,
  });

  final int? id;
  final String name;
  final double targetAmount;
  final double savedAmount;
  final DateTime? deadline;
  final String iconKey;
  final int colorValue;
  final bool completed;

  double get progress => targetAmount <= 0
      ? 0
      : (savedAmount / targetAmount).clamp(0.0, 1.0).toDouble();
  double get remaining =>
      (targetAmount - savedAmount).clamp(0.0, double.infinity).toDouble();

  factory SavingsGoal.fromMap(Map<String, Object?> map) => SavingsGoal(
    id: (map['id'] as num).toInt(),
    name: map['name'] as String,
    targetAmount: (map['target_amount'] as num).toDouble(),
    savedAmount: (map['saved_amount'] as num).toDouble(),
    deadline: map['deadline_ms'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (map['deadline_ms'] as num).toInt(),
          ),
    iconKey: map['icon_key'] as String,
    colorValue: (map['color_value'] as num).toInt(),
    completed: (map['completed'] as num).toInt() == 1,
  );
}

class SavingsGoalsRepository {
  Future<List<SavingsGoal>> getAll() async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'savings_goals',
      orderBy: 'completed ASC, created_at_ms DESC',
    );
    return rows.map(SavingsGoal.fromMap).toList(growable: false);
  }

  Future<int> create(SavingsGoal goal) async {
    final db = await AppDb.instance;
    return db.insert('savings_goals', {
      'name': goal.name.trim(),
      'target_amount': goal.targetAmount,
      'saved_amount': goal.savedAmount,
      'deadline_ms': goal.deadline?.millisecondsSinceEpoch,
      'icon_key': goal.iconKey,
      'color_value': goal.colorValue,
      'completed': goal.savedAmount >= goal.targetAmount ? 1 : 0,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> contribute(int goalId, double amount, {String? note}) async {
    final db = await AppDb.instance;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'savings_goals',
        columns: ['saved_amount', 'target_amount'],
        where: 'id = ?',
        whereArgs: [goalId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final current = (rows.single['saved_amount'] as num).toDouble();
      final target = (rows.single['target_amount'] as num).toDouble();
      final next = (current + amount).clamp(0.0, double.infinity).toDouble();
      await txn.update(
        'savings_goals',
        {'saved_amount': next, 'completed': next >= target ? 1 : 0},
        where: 'id = ?',
        whereArgs: [goalId],
      );
      await txn.insert('savings_goal_contributions', {
        'goal_id': goalId,
        'amount': amount,
        'note': note?.trim(),
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> delete(int id) async {
    final db = await AppDb.instance;
    await db.delete('savings_goals', where: 'id = ?', whereArgs: [id]);
  }
}
