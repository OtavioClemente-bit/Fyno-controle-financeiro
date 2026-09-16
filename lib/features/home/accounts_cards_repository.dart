import '../../core/db/app_db.dart';
import 'models/tx_item.dart';

class FinancialAccount {
  const FinancialAccount({
    this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.colorValue,
  });

  final int? id;
  final String name;
  final String type;
  final double initialBalance;
  final int colorValue;

  factory FinancialAccount.fromMap(Map<String, Object?> map) =>
      FinancialAccount(
        id: (map['id'] as num?)?.toInt(),
        name: map['name'] as String,
        type: map['type'] as String,
        initialBalance: (map['initial_balance'] as num).toDouble(),
        colorValue: (map['color_value'] as num).toInt(),
      );
}

class CreditCardItem {
  const CreditCardItem({
    this.id,
    required this.name,
    required this.brand,
    this.lastFour,
    required this.limitAmount,
    required this.closingDay,
    required this.dueDay,
    this.accountId,
    required this.colorValue,
  });

  final int? id;
  final String name;
  final String brand;
  final String? lastFour;
  final double limitAmount;
  final int closingDay;
  final int dueDay;
  final int? accountId;
  final int colorValue;

  String get displayName =>
      lastFour == null || lastFour!.isEmpty ? name : '$name •••• $lastFour';

  factory CreditCardItem.fromMap(Map<String, Object?> map) => CreditCardItem(
    id: (map['id'] as num?)?.toInt(),
    name: map['name'] as String,
    brand: map['brand'] as String,
    lastFour: map['last_four'] as String?,
    limitAmount: (map['limit_amount'] as num).toDouble(),
    closingDay: (map['closing_day'] as num).toInt(),
    dueDay: (map['due_day'] as num).toInt(),
    accountId: (map['account_id'] as num?)?.toInt(),
    colorValue: (map['color_value'] as num).toInt(),
  );
}

class CardSummary {
  const CardSummary({
    required this.card,
    required this.purchases,
    required this.payments,
  });
  final CreditCardItem card;
  final double purchases;
  final double payments;
  double get outstanding =>
      (purchases - payments).clamp(0, double.infinity).toDouble();
  double get available =>
      (card.limitAmount - outstanding).clamp(0, double.infinity).toDouble();
}

class CardInvoice {
  const CardInvoice({
    required this.card,
    required this.month,
    required this.purchases,
    required this.payments,
  });
  final CreditCardItem card;
  final DateTime month;
  final List<TxItem> purchases;
  final List<TxItem> payments;
  double get purchaseTotal =>
      purchases.fold(0.0, (sum, item) => sum + item.amount);
  double get paymentTotal =>
      payments.fold(0.0, (sum, item) => sum + item.amount);
  double get remaining =>
      (purchaseTotal - paymentTotal).clamp(0, double.infinity).toDouble();
}

class AccountsCardsRepository {
  Future<List<FinancialAccount>> getAccounts() async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'financial_accounts',
      where: 'active = 1',
      orderBy: 'LOWER(name)',
    );
    return rows.map(FinancialAccount.fromMap).toList(growable: false);
  }

  Future<int> saveAccount(FinancialAccount account) async {
    final db = await AppDb.instance;
    final values = <String, Object?>{
      'name': account.name.trim(),
      'type': account.type,
      'initial_balance': account.initialBalance,
      'color_value': account.colorValue,
      'active': 1,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (account.id == null) return db.insert('financial_accounts', values);
    values.remove('created_at_ms');
    await db.update(
      'financial_accounts',
      values,
      where: 'id = ?',
      whereArgs: [account.id],
    );
    return account.id!;
  }

  Future<double> getAccountBalance(FinancialAccount account) async {
    if (account.id == null) return account.initialBalance;
    final db = await AppDb.instance;
    final rows = await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [account.id],
    );
    var balance = account.initialBalance;
    for (final row in rows) {
      final tx = TxItem.fromMap(row);
      if (tx.isIncome) {
        balance += tx.amount;
      } else if (!tx.isCreditPurchase) {
        // A compra no crédito afeta o limite. A conta só é debitada ao pagar
        // a fatura, evitando descontar o mesmo dinheiro duas vezes.
        balance -= tx.amount;
      }
    }
    return balance;
  }

  Future<List<CreditCardItem>> getCards() async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'credit_cards',
      where: 'active = 1',
      orderBy: 'LOWER(name)',
    );
    return rows.map(CreditCardItem.fromMap).toList(growable: false);
  }

  Future<int> saveCard(CreditCardItem card) async {
    final db = await AppDb.instance;
    final values = <String, Object?>{
      'name': card.name.trim(),
      'brand': card.brand,
      'last_four': card.lastFour?.trim(),
      'limit_amount': card.limitAmount,
      'closing_day': card.closingDay.clamp(1, 31),
      'due_day': card.dueDay.clamp(1, 31),
      'account_id': card.accountId,
      'color_value': card.colorValue,
      'active': 1,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (card.id == null) return db.insert('credit_cards', values);
    values.remove('created_at_ms');
    await db.update(
      'credit_cards',
      values,
      where: 'id = ?',
      whereArgs: [card.id],
    );
    return card.id!;
  }

  Future<List<CardSummary>> getCardSummaries() async {
    final cards = await getCards();
    final db = await AppDb.instance;
    final rows = await db.query(
      'transactions',
      where: 'credit_card_id IS NOT NULL',
    );
    final transactions = rows.map(TxItem.fromMap).toList();
    return [
      for (final card in cards)
        CardSummary(
          card: card,
          purchases: transactions
              .where((tx) => tx.creditCardId == card.id && tx.isCreditPurchase)
              .fold(0.0, (sum, tx) => sum + tx.amount),
          payments: transactions
              .where(
                (tx) =>
                    tx.creditCardId == card.id && tx.isCreditCardBillPayment,
              )
              .fold(0.0, (sum, tx) => sum + tx.amount),
        ),
    ];
  }

  int invoiceKeyFor(CreditCardItem card, DateTime purchaseDate) {
    final month = purchaseDate.day > card.closingDay
        ? DateTime(purchaseDate.year, purchaseDate.month + 1)
        : DateTime(purchaseDate.year, purchaseDate.month);
    return month.year * 100 + month.month;
  }

  Future<CardInvoice> getInvoice(CreditCardItem card, DateTime month) async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'transactions',
      where: 'credit_card_id = ?',
      whereArgs: [card.id],
      orderBy: 'date_ms DESC, id DESC',
    );
    final all = rows.map(TxItem.fromMap).toList();
    final key = month.year * 100 + month.month;
    final purchases = all
        .where(
          (tx) => tx.isCreditPurchase && invoiceKeyFor(card, tx.date) == key,
        )
        .toList();
    final payments = all
        .where(
          (tx) =>
              tx.isCreditCardBillPayment &&
              tx.date.year == month.year &&
              tx.date.month == month.month,
        )
        .toList();
    return CardInvoice(
      card: card,
      month: month,
      purchases: purchases,
      payments: payments,
    );
  }

  Future<void> archiveCard(int id) async {
    final db = await AppDb.instance;
    await db.update(
      'credit_cards',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
