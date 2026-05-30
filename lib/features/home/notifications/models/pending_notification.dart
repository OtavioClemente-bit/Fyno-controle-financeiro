class PendingNotification {
  final int id;
  final String notifKey;
  final String packageName;
  final String? title;
  final String? text;
  final int postedAtMs;

  final double? parsedAmount;
  final int? parsedIsIncome; // 1=receita, 0=despesa, null=desconhecido
  final String? parsedMethod; // pix/cartao/null

  final String status; // pending/imported/ignored
  final int? importedTxId;

  PendingNotification({
    required this.id,
    required this.notifKey,
    required this.packageName,
    required this.title,
    required this.text,
    required this.postedAtMs,
    required this.parsedAmount,
    required this.parsedIsIncome,
    required this.parsedMethod,
    required this.status,
    required this.importedTxId,
  });

  factory PendingNotification.fromMap(Map<String, dynamic> m) {
    return PendingNotification(
      id: (m['id'] as int),
      notifKey: (m['notif_key'] as String),
      packageName: (m['package_name'] as String),
      title: m['title'] as String?,
      text: m['text'] as String?,
      postedAtMs: (m['posted_at_ms'] as int),
      parsedAmount: (m['parsed_amount'] as num?)?.toDouble(),
      parsedIsIncome: m['parsed_is_income'] as int?,
      parsedMethod: m['parsed_method'] as String?,
      status: (m['status'] as String?) ?? 'pending',
      importedTxId: m['imported_tx_id'] as int?,
    );
  }
}
