import 'notification_bridge.dart';
import 'repositories/notification_import_repository.dart';
import 'transaction_category_suggester.dart';
import 'repositories/smart_rules_repository.dart';

class NotificationInboxService {
  NotificationInboxService({
    NotificationImportRepository? repository,
    NotificationBridge? bridge,
  }) : _repository = repository ?? NotificationImportRepository(),
       _bridge = bridge ?? NotificationBridge.instance;

  final NotificationImportRepository _repository;
  final NotificationBridge _bridge;
  final SmartRulesRepository _rules = SmartRulesRepository();

  Future<int> sync() async {
    final captureEnabled = await _bridge.isCaptureEnabled();
    final allowed = await _repository.getEnabledPackages();
    await _bridge.setAllowedPackages(allowed);

    if (!captureEnabled || allowed.isEmpty) {
      await _bridge.clearBufferedNotifications();
      return _repository.countPending();
    }

    final buffered = await _bridge.drainBufferedNotifications();
    final rows = <Map<String, Object?>>[];

    for (final item in buffered) {
      final packageName = '${item['package_name'] ?? ''}'.trim();
      final key = '${item['notif_key'] ?? ''}'.trim();
      final amount = _asDouble(item['parsed_amount']);
      final isIncome = _asBool(item['parsed_is_income']);
      if (!allowed.contains(packageName) ||
          key.isEmpty ||
          amount == null ||
          amount <= 0) {
        continue;
      }

      final title = '${item['title'] ?? ''}'.trim();
      final text = '${item['text'] ?? ''}'.trim();
      final learned = await _rules.findFor(title, text);
      final suggestion = TransactionCategorySuggester.suggest(
        text: '$title $text',
        isIncome: isIncome,
      );

      rows.add({
        'notif_key': key,
        'package_name': packageName,
        'title': title,
        'text': text,
        'posted_at_ms':
            _asInt(item['posted_at_ms']) ??
            DateTime.now().millisecondsSinceEpoch,
        'parsed_amount': amount,
        'parsed_is_income': learned != null
            ? (learned.isIncome ? 1 : 0)
            : (isIncome == null ? null : (isIncome ? 1 : 0)),
        'parsed_method':
            learned?.paymentMethod ?? '${item['parsed_method'] ?? ''}'.trim(),
        'suggested_category': learned?.category ?? suggestion.category,
        'reminder_at_ms': null,
        'status': 'pending',
        'imported_tx_id': null,
      });
    }

    await _repository.insertPendingMany(rows);
    return _repository.countPending();
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  bool? _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value == 'true') return true;
    if (value == 'false') return false;
    return null;
  }
}
