import 'package:controle_financeiro/features/home/models/tx_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TxItem expense(String paymentMethod) => TxItem(
    title: 'Lançamento',
    amount: 100,
    isIncome: false,
    date: DateTime(2026, 8, 28),
    category: 'Contas',
    paymentMethod: paymentMethod,
  );

  test('compra no crédito continua sendo despesa', () {
    final item = expense(TxItem.creditPaymentMethod);

    expect(item.isCreditPurchase, isTrue);
    expect(item.isCreditCardBillPayment, isFalse);
    expect(item.countsAsExpense, isTrue);
  });

  test('pagamento da fatura quita o cartão sem duplicar despesa', () {
    final item = expense(TxItem.creditCardBillPaymentMethod);

    expect(item.isCreditPurchase, isFalse);
    expect(item.isCreditCardBillPayment, isTrue);
    expect(item.countsAsExpense, isFalse);
  });
}
