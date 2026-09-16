import 'package:controle_financeiro/features/home/confirm_receipt_items_page.dart';
import 'package:controle_financeiro/features/home/receipt_item_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('melhora nomes e mantém o original disponível', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ConfirmReceiptItemsPage(
          initialItems: [
            ReceiptItemDraft(
              name: 'REFR COCA COLA LT 350ML',
              price: 4.5,
              qty: 1,
              unit: 'UN',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Melhorar nomes dos produtos'));
    await tester.pumpAndSettle();

    expect(find.text('Refrigerante Coca-Cola Lata 350 ml'), findsOneWidget);
    expect(find.text('Na nota: REFR COCA COLA LT 350ML'), findsOneWidget);

    final restore = find.byTooltip('Restaurar nome da nota');
    await tester.ensureVisible(restore);
    await tester.pumpAndSettle();
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('REFR COCA COLA LT 350ML'), findsOneWidget);
  });
}
