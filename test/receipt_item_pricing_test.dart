import 'package:controle_financeiro/features/home/receipt_item_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiptItemDraft pricing', () {
    test('divide o total pela quantidade', () {
      final item = ReceiptItemDraft.fromLineTotal(
        name: 'Sabonete',
        total: 19.98,
        qty: 2,
        unit: 'UN',
      );

      expect(item.price, 9.99);
      expect(item.effectiveLineTotal, 19.98);
      expect(item.wasUnitPriceCalculated, isTrue);
    });

    test('calcula corretamente produto vendido por peso', () {
      final item = ReceiptItemDraft.fromLineTotal(
        name: 'Queijo',
        total: 10.43,
        qty: .7,
        unit: 'KG',
      );

      expect(item.price, 14.9);
      expect(item.effectiveLineTotal, 10.43);
    });

    test('recalcula o unitário quando a quantidade é corrigida', () {
      final item = ReceiptItemDraft.fromLineTotal(name: 'Produto', total: 30);

      item.setQuantity(3);

      expect(item.price, 10);
      expect(item.effectiveLineTotal, 30);
    });

    test('edição manual do unitário atualiza o total', () {
      final item = ReceiptItemDraft.fromLineTotal(
        name: 'Produto',
        total: 20,
        qty: 2,
      );

      item.setUnitPrice(12);

      expect(item.price, 12);
      expect(item.effectiveLineTotal, 24);
      expect(item.priceSource, ReceiptPriceSource.manual);
    });
  });
}
