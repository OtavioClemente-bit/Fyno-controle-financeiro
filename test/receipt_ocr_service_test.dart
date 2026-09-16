import 'package:controle_financeiro/features/home/receipt_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiptOcrService pricing', () {
    test('lê quantidade, unitário e total em duas linhas', () {
      final items = ReceiptOcrService.parseRecognizedText('''
REFR COCA COLA LT 350ML
2 UN X 5,99 11,98
TOTAL A PAGAR 11,98
''');

      expect(items, hasLength(1));
      expect(items.single.qty, 2);
      expect(items.single.price, 5.99);
      expect(items.single.effectiveLineTotal, 11.98);
    });

    test('divide total quando não existe preço unitário', () {
      final items = ReceiptOcrService.parseRecognizedText(
        'ARROZ T1 QTD. 3 UN VL TOTAL R\$ 29,97',
      );

      expect(items, hasLength(1));
      expect(items.single.name, 'ARROZ T1');
      expect(items.single.qty, 3);
      expect(items.single.price, 9.99);
      expect(items.single.wasUnitPriceCalculated, isTrue);
    });

    test('prioriza preço unitário explícito em produto por peso', () {
      final items = ReceiptOcrService.parseRecognizedText('''
QUEIJO MUSSARELA
QTDE: 0,750 KG VL UNITARIO 39,90 VL TOTAL 29,93
''');

      expect(items, hasLength(1));
      expect(items.single.qty, .75);
      expect(items.single.unit, 'KG');
      expect(items.single.price, 39.9);
      expect(items.single.effectiveLineTotal, 29.93);
    });

    test('divide linha simples com quantidade em unidades', () {
      final items = ReceiptOcrService.parseRecognizedText(
        'SABONETE 3 UN 10,50',
      );

      expect(items, hasLength(1));
      expect(items.single.name, 'SABONETE');
      expect(items.single.qty, 3);
      expect(items.single.price, 3.5);
    });
  });
}
