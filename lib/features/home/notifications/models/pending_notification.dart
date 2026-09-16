class PendingNotification {
  final int? id;
  final String notifKey;
  final String packageName;
  final String title;
  final String text;
  final int postedAtMs;

  final double? parsedAmount;
  final bool? parsedIsIncome;
  final String? parsedMethod;
  final String? suggestedCategory;
  final String status;
  final int? reminderAtMs;

  PendingNotification({
    this.id,
    required this.notifKey,
    required this.packageName,
    required this.title,
    required this.text,
    required this.postedAtMs,
    this.parsedAmount,
    this.parsedIsIncome,
    this.parsedMethod,
    this.suggestedCategory,
    this.status = 'pending',
    this.reminderAtMs,
  });

  factory PendingNotification.fromMap(Map<String, Object?> m) {
    return PendingNotification(
      id: m['id'] as int?,
      notifKey: (m['notif_key'] ?? '') as String,
      packageName: (m['package_name'] ?? '') as String,
      title: (m['title'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      postedAtMs: (m['posted_at_ms'] ?? 0) as int,
      parsedAmount: (m['parsed_amount'] as num?)?.toDouble(),
      parsedIsIncome: m['parsed_is_income'] == null
          ? null
          : ((m['parsed_is_income'] as int) == 1),
      parsedMethod: m['parsed_method'] as String?,
      suggestedCategory: m['suggested_category'] as String?,
      status: (m['status'] as String?) ?? 'pending',
      reminderAtMs: (m['reminder_at_ms'] as num?)?.toInt(),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'notif_key': notifKey,
    'package_name': packageName,
    'title': title,
    'text': text,
    'posted_at_ms': postedAtMs,
    'parsed_amount': parsedAmount,
    'parsed_is_income': parsedIsIncome == null
        ? null
        : (parsedIsIncome! ? 1 : 0),
    'parsed_method': parsedMethod,
    'suggested_category': suggestedCategory,
    'status': status,
    'reminder_at_ms': reminderAtMs,
  };

  bool get hasReminder => reminderAtMs != null;

  bool get reminderIsDue =>
      reminderAtMs != null &&
      reminderAtMs! <= DateTime.now().millisecondsSinceEpoch;
}
