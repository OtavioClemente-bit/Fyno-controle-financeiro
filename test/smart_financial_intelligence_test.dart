import 'package:flutter_test/flutter_test.dart';
import 'package:controle_financeiro/features/home/models/tx_item.dart';
import 'package:controle_financeiro/features/home/notifications/models/recurring_transaction_detector.dart';
import 'package:controle_financeiro/features/home/notifications/models/smart_transaction_rule.dart';

void main() {
  test('extracts a stable merchant identity while ignoring the amount', () {
    final first = MerchantIdentity.extract(
      '',
      'Compra aprovada em Netflix R\$ 39,90',
    );
    final second = MerchantIdentity.extract(
      '',
      'Compra aprovada em Netflix R\$ 45,90',
    );
    expect(first?.key, 'netflix');
    expect(second?.key, first?.key);
  });

  test('detects a monthly subscription with a stable amount', () {
    final transactions = [
      _tx(DateTime(2026, 5, 10), 39.90),
      _tx(DateTime(2026, 6, 10), 39.90),
      _tx(DateTime(2026, 7, 10), 39.90),
    ];
    final detected = RecurringTransactionDetector.detect(transactions);
    expect(detected, hasLength(1));
    expect(detected.single.cadence, RecurrenceCadence.monthly);
    expect(detected.single.isSubscription, isTrue);
    expect(detected.single.occurrences, 3);
  });

  test('does not flag irregular purchases as recurring', () {
    final transactions = [
      _tx(DateTime(2026, 5, 1), 20),
      _tx(DateTime(2026, 5, 18), 80),
      _tx(DateTime(2026, 7, 20), 15),
    ];
    expect(RecurringTransactionDetector.detect(transactions), isEmpty);
  });
}

TxItem _tx(DateTime date, double amount) => TxItem(
  title: 'Netflix',
  amount: amount,
  isIncome: false,
  date: date,
  category: 'Lazer',
);
