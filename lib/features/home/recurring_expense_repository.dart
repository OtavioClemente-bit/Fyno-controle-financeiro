import '../../core/db/app_db.dart';
import 'dart:typed_data';
import 'models/tx_item.dart';
import 'notifications/models/smart_transaction_rule.dart';

class RecurringExpense {
  const RecurringExpense({
    this.id,
    required this.name,
    required this.amount,
    required this.category,
    required this.dueDay,
    this.active = true,
    this.note,
    this.iconImage,
    this.paymentMethod = 'Pix',
    this.creditCardId,
  });

  final int? id;
  final String name;
  final double amount;
  final String category;
  final int dueDay;
  final bool active;
  final String? note;
  final Uint8List? iconImage;
  final String paymentMethod;
  final int? creditCardId;

  factory RecurringExpense.fromMap(Map<String, Object?> map) =>
      RecurringExpense(
        id: (map['id'] as num?)?.toInt(),
        name: map['name'] as String,
        amount: (map['amount'] as num).toDouble(),
        category: map['category'] as String,
        dueDay: (map['due_day'] as num).toInt(),
        active: (map['active'] as num?)?.toInt() != 0,
        note: map['note'] as String?,
        iconImage: map['icon_image'] as Uint8List?,
        paymentMethod: (map['payment_method'] as String?) ?? 'Pix',
        creditCardId: (map['credit_card_id'] as num?)?.toInt(),
      );
}

class RecurringExpenseRepository {
  Future<List<RecurringExpense>> getAll() async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'recurring_expenses',
      where: 'active = 1',
      orderBy: 'due_day ASC, LOWER(name) ASC',
    );
    return rows.map(RecurringExpense.fromMap).toList(growable: false);
  }

  Future<void> save(RecurringExpense item) async {
    final db = await AppDb.instance;
    final values = <String, Object?>{
      'name': item.name.trim(),
      'amount': item.amount,
      'category': item.category,
      'due_day': item.dueDay.clamp(1, 31),
      'active': item.active ? 1 : 0,
      'note': item.note?.trim(),
      'icon_image': item.iconImage,
      'payment_method': item.paymentMethod,
      'credit_card_id': item.creditCardId,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (item.id == null) {
      await db.insert('recurring_expenses', values);
    } else {
      values.remove('created_at_ms');
      await db.update(
        'recurring_expenses',
        values,
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
  }

  Future<void> archive(int id) async {
    final db = await AppDb.instance;
    await db.update(
      'recurring_expenses',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> isPaidThisMonth(RecurringExpense item, DateTime month) async {
    final db = await AppDb.instance;
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final rows = await db.query(
      'transactions',
      columns: const ['title'],
      where: 'is_income = 0 AND date_ms >= ? AND date_ms < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    final key = MerchantIdentity.normalize(item.name);
    return rows.any(
      (row) => MerchantIdentity.normalize('${row['title']}') == key,
    );
  }

  Future<void> markPaid(RecurringExpense item, DateTime month) async {
    if (await isPaidThisMonth(item, month)) return;
    final now = DateTime.now();
    final maxDay = DateTime(month.year, month.month + 1, 0).day;
    final date = month.year == now.year && month.month == now.month
        ? now
        : DateTime(month.year, month.month, item.dueDay.clamp(1, maxDay));
    final db = await AppDb.instance;
    await db.insert(
      'transactions',
      TxItem(
        title: item.name,
        amount: item.amount,
        isIncome: false,
        date: date,
        category: item.category,
        note: 'Pagamento recorrente registrado pelo Fyno',
        paymentMethod: item.paymentMethod,
        creditCardId: item.creditCardId,
      ).toMap()..remove('id'),
    );
  }
}
