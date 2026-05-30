class TxItem {
  final int? id;
  final String title;
  final double amount;
  final bool isIncome;
  final DateTime date;
  final String category;
  final String? note;
  final String? receiptImagePath;

  // ✅ NOVOS CAMPOS
  final String paymentMethod; // ex: pix | debit | cash | credit
  final int? creditCardId; // se paymentMethod == 'credit'
  final int? installments; // parcelamento (opcional)

  const TxItem({
    this.id,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.date,
    required this.category,
    this.note,
    this.receiptImagePath,

    // ✅ defaults seguros
    this.paymentMethod = 'pix',
    this.creditCardId,
    this.installments,
  });

  /// Converte para Map (SQLite)
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'is_income': isIncome ? 1 : 0,
      'date_ms': date.millisecondsSinceEpoch,
      'category': category,
      'note': note,
      'receipt_image_path': receiptImagePath,

      // ✅ NOVOS CAMPOS
      'payment_method': paymentMethod,
      'credit_card_id': creditCardId,
      'installments': installments,
    };
  }

  /// Cria a partir do Map (SQLite → Dart)
  factory TxItem.fromMap(Map<String, Object?> map) {
    return TxItem(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      isIncome: (map['is_income'] as int) == 1,
      date: DateTime.fromMillisecondsSinceEpoch(
        (map['date_ms'] as num).toInt(),
      ),
      category: map['category'] as String,
      note: map['note'] as String?,
      receiptImagePath: map['receipt_image_path'] as String?,

      // ✅ NOVOS CAMPOS (com fallback seguro)
      paymentMethod: (map['payment_method'] as String?) ?? 'pix',
      creditCardId: (map['credit_card_id'] as num?)?.toInt(),
      installments: (map['installments'] as num?)?.toInt(),
    );
  }

  /// Útil para edição (copy sem mutar o objeto original)
  TxItem copyWith({
    int? id,
    String? title,
    double? amount,
    bool? isIncome,
    DateTime? date,
    String? category,
    String? note,
    String? receiptImagePath,

    // ✅ novos
    String? paymentMethod,
    int? creditCardId,
    int? installments,
  }) {
    return TxItem(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      isIncome: isIncome ?? this.isIncome,
      date: date ?? this.date,
      category: category ?? this.category,
      note: note ?? this.note,
      receiptImagePath: receiptImagePath ?? this.receiptImagePath,

      // ✅ novos
      paymentMethod: paymentMethod ?? this.paymentMethod,
      creditCardId: creditCardId ?? this.creditCardId,
      installments: installments ?? this.installments,
    );
  }
}
