import 'package:controle_financeiro/features/home/product_name_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatProductNameLocally', () {
    test('expande abreviações comuns de refrigerante', () {
      expect(
        formatProductNameLocally('001 REFR COCA COLA LT 350ML'),
        'Refrigerante Coca-Cola Lata 350 ml',
      );
    });

    test('formata alimentos, tipo e peso', () {
      expect(
        formatProductNameLocally('ARROZ T1 PCT 5KG'),
        'Arroz Tipo 1 Pacote 5 kg',
      );
    });

    test('preserva siglas úteis', () {
      expect(
        formatProductNameLocally('LEITE INT UHT 1L'),
        'Leite Integral UHT 1 L',
      );
    });

    test('remove código fiscal anexado ao nome', () {
      expect(
        formatProductNameLocally('BISC RECH CHOC (CODIGO: 1234)'),
        'Biscoito Recheado Chocolate',
      );
    });
  });
}
