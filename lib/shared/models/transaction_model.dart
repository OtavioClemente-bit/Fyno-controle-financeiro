enum TxType { income, expense }

class TransactionModel {
  final String title;
  final String category;
  final DateTime date;
  final double amount;
  final TxType type;

  const TransactionModel({
    required this.title,
    required this.category,
    required this.date,
    required this.amount,
    required this.type,
  });
}
