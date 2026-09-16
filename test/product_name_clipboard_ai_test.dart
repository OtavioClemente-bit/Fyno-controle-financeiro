import 'package:controle_financeiro/features/home/product_name_clipboard_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prompt numera produtos e exige JSON', () {
    final prompt = ProductNameClipboardAi.buildPrompt([
      'REFR COCA LT 350ML',
      'ARROZ T1 5KG',
    ]);
    expect(prompt, contains('"id": 1'));
    expect(prompt, contains('REFR COCA LT 350ML'));
    expect(prompt, contains('SOMENTE com um array JSON válido'));
  });

  test('interpreta JSON mesmo dentro de bloco de markdown e fora de ordem', () {
    final result = ProductNameClipboardAi.parseResponse(
      'Aqui está:\n```json\n'
      '[{"id":2,"nome":"Arroz Tipo 1 5 kg"},'
      '{"id":1,"nome":"Refrigerante Coca-Cola Lata 350 ml"}]\n```',
      itemCount: 2,
    );
    expect(result.namesByIndex[0], 'Refrigerante Coca-Cola Lata 350 ml');
    expect(result.namesByIndex[1], 'Arroz Tipo 1 5 kg');
    expect(result.ignoredEntries, 0);
  });

  test('ignora IDs desconhecidos sem alterar os demais', () {
    final result = ProductNameClipboardAi.parseResponse(
      '[{"id":1,"nome":"Leite Integral 1 L"},'
      '{"id":99,"nome":"Invasor"}]',
      itemCount: 2,
    );
    expect(result.namesByIndex, {0: 'Leite Integral 1 L'});
    expect(result.ignoredEntries, 1);
  });
}
