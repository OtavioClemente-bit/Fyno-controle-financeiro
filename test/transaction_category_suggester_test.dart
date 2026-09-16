import 'package:controle_financeiro/features/home/notifications/models/transaction_category_suggester.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransactionCategorySuggester', () {
    test('sugere alimentação pelo estabelecimento', () {
      final result = TransactionCategorySuggester.suggest(
        text: 'Compra aprovada de R\$ 42,90 no iFood',
        isIncome: false,
      );

      expect(result.category, 'Alimentação');
      expect(result.confidence, greaterThan(.65));
    });

    test('sugere combustível sem enviar dados para fora', () {
      final result = TransactionCategorySuggester.suggest(
        text: 'Compra no Posto Ipiranga - gasolina',
        isIncome: false,
      );

      expect(result.category, 'Combustível');
      expect(result.confidence, greaterThan(.75));
    });

    test('diferencia salário de uma entrada genérica', () {
      expect(
        TransactionCategorySuggester.suggest(
          text: 'Crédito de folha de pagamento salarial',
          isIncome: true,
        ).category,
        'Salário',
      );
      expect(
        TransactionCategorySuggester.suggest(
          text: 'Pix recebido',
          isIncome: true,
        ).category,
        'Outros',
      );
    });

    test('não confunde transação com ação de investimento', () {
      final result = TransactionCategorySuggester.suggest(
        text: 'Item de teste — não é uma transação real',
        isIncome: false,
      );

      expect(result.category, 'Outros');
    });
  });
}
