import 'package:controle_financeiro/features/home/accounts_cards_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const card = CreditCardItem(
    id: 1,
    name: 'Principal',
    brand: 'Mastercard',
    limitAmount: 5000,
    closingDay: 20,
    dueDay: 28,
    colorValue: 0xFF123F36,
  );

  test('compra até o fechamento entra na fatura do mês', () {
    final key = AccountsCardsRepository().invoiceKeyFor(
      card,
      DateTime(2026, 8, 20),
    );
    expect(key, 202608);
  });

  test('compra após o fechamento entra na próxima fatura', () {
    final key = AccountsCardsRepository().invoiceKeyFor(
      card,
      DateTime(2026, 8, 21),
    );
    expect(key, 202609);
  });
}
