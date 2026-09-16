import '../../models/tx_item.dart';
import 'smart_transaction_rule.dart';

enum RecurrenceCadence { weekly, monthly, yearly }

class RecurringTransactionCandidate {
  const RecurringTransactionCandidate({
    required this.key,
    required this.title,
    required this.category,
    required this.averageAmount,
    required this.cadence,
    required this.occurrences,
    required this.lastDate,
    required this.nextExpectedDate,
    required this.confidence,
    required this.isSubscription,
  });

  final String key;
  final String title;
  final String category;
  final double averageAmount;
  final RecurrenceCadence cadence;
  final int occurrences;
  final DateTime lastDate;
  final DateTime nextExpectedDate;
  final double confidence;
  final bool isSubscription;
}

class RecurringTransactionDetector {
  static List<RecurringTransactionCandidate> detect(List<TxItem> transactions) {
    final groups = <String, List<TxItem>>{};
    for (final tx in transactions.where((item) => !item.isIncome)) {
      final key = MerchantIdentity.normalize(tx.title);
      if (key.length < 3) continue;
      groups.putIfAbsent(key, () => []).add(tx);
    }

    final result = <RecurringTransactionCandidate>[];
    for (final entry in groups.entries) {
      final items = entry.value..sort((a, b) => a.date.compareTo(b.date));
      if (items.length < 2) continue;
      final intervals = <int>[];
      for (var i = 1; i < items.length; i++) {
        intervals.add(items[i].date.difference(items[i - 1].date).inDays.abs());
      }
      final medianDays = _median(intervals);
      final cadence = switch (medianDays) {
        >= 6 && <= 8 => RecurrenceCadence.weekly,
        >= 26 && <= 35 => RecurrenceCadence.monthly,
        >= 350 && <= 380 => RecurrenceCadence.yearly,
        _ => null,
      };
      if (cadence == null) continue;
      final average =
          items.fold<double>(0, (sum, tx) => sum + tx.amount) / items.length;
      final maxDeviation = items
          .map((tx) => (tx.amount - average).abs() / average)
          .fold<double>(0, (max, value) => value > max ? value : max);
      final variableBill = items.last.category == 'Contas';
      if (maxDeviation > (variableBill ? .35 : .18)) continue;
      final expectedDays = switch (cadence) {
        RecurrenceCadence.weekly => 7,
        RecurrenceCadence.monthly => 30,
        RecurrenceCadence.yearly => 365,
      };
      final intervalConsistency =
          intervals
              .where(
                (days) =>
                    (days - expectedDays).abs() <=
                    (cadence == RecurrenceCadence.monthly ? 5 : 2),
              )
              .length /
          intervals.length;
      final last = items.last;
      result.add(
        RecurringTransactionCandidate(
          key: entry.key,
          title: last.title,
          category: last.category,
          averageAmount: average,
          cadence: cadence,
          occurrences: items.length,
          lastDate: last.date,
          nextExpectedDate: last.date.add(Duration(days: expectedDays)),
          confidence:
              (.62 + (items.length - 2) * .09 + intervalConsistency * .18)
                  .clamp(.0, .98),
          isSubscription: !variableBill && maxDeviation <= .08,
        ),
      );
    }
    result.sort((a, b) => b.confidence.compareTo(a.confidence));
    return result;
  }

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }
}
