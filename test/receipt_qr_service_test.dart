import 'package:controle_financeiro/features/home/receipt_qr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiptQrService.isWebQrValue', () {
    test('accepts NFC-e web URLs with fiscal parameters', () {
      expect(
        ReceiptQrService.isWebQrValue(
          'https://portalsped.fazenda.mg.gov.br/portalnfce/sistema/qrcode.xhtml?p=123|2|1',
        ),
        isTrue,
      );
    });

    test('accepts http and trims line breaks', () {
      expect(
        ReceiptQrService.isWebQrValue('  http://www.fazenda.gov.br/nfce\n'),
        isTrue,
      );
    });

    test('accepts an official fiscal link pasted without scheme', () {
      expect(
        ReceiptQrService.isWebQrValue(
          'www.fazenda.sp.gov.br/nfce/qrcode?p=123|2|1',
        ),
        isTrue,
      );
    });

    test('rejects text, unsafe schemes and URLs without host', () {
      expect(ReceiptQrService.isWebQrValue('123456789'), isFalse);
      expect(ReceiptQrService.isWebQrValue('javascript:alert(1)'), isFalse);
      expect(ReceiptQrService.isWebQrValue('https:///cupom'), isFalse);
      expect(
        ReceiptQrService.isWebQrValue('https://example.com/cupom'),
        isFalse,
      );
      expect(
        ReceiptQrService.isWebQrValue('https://www.gov.br/pt-br'),
        isFalse,
      );
    });
  });

  group('ReceiptQrService item pricing', () {
    test('divide o total do portal pela quantidade comprada', () {
      final items = ReceiptQrService.parseHtmlForTesting('''
        <table><tr>
          <td>SABONETE</td>
          <td>Qtde total de itens: 3</td>
          <td>UN: UN</td>
          <td>Valor total R\$: R\$ 10,50</td>
        </tr></table>
      ''');

      expect(items, hasLength(1));
      expect(items.single.qty, 3);
      expect(items.single.price, 3.5);
      expect(items.single.effectiveLineTotal, 10.5);
      expect(items.single.wasUnitPriceCalculated, isTrue);
    });

    test('extrai itens do layout em blocos usado pelo portal da SEF/MG', () {
      final items = ReceiptQrService.parseHtmlForTesting('''
        <html><body>
          <div class="item">
            <span>LEITE INTEGRAL 1L</span>
            <span>(Código: 12345)</span>
            <span>Qtde total de ítens:</span><span>2.0000</span>
            <span>UN:</span><span>UN</span>
            <span>Valor total R\$:</span><span>R\$ 11,98</span>
          </div>
          <div class="item">
            <span>BANANA PRATA kg</span>
            <span>(Código: 77)</span>
            <span>Qtde total de ítens: 1.2500</span>
            <span>UN: KG</span>
            <span>Valor total R\$: R\$ 8,75</span>
          </div>
        </body></html>
      ''');

      expect(items, hasLength(2));
      expect(items.first.name, 'LEITE INTEGRAL 1L');
      expect(items.first.qty, 2);
      expect(items.first.price, 5.99);
      expect(items.last.name, 'BANANA PRATA kg');
      expect(items.last.qty, 1.25);
      expect(items.last.price, 7);
    });

    test('extrai o layout padrão de portais NFC-e estaduais', () {
      final items = ReceiptQrService.parseHtmlForTesting('''
        <table><tr id="Item + 1">
          <td>
            <span class="txtTit">CAFÉ TORRADO 500G</span>
            <span class="RCod">(Código: 789)</span>
            <span class="Rqtd"><strong>Qtde.:</strong> 2</span>
            <span class="RUN"><strong>UN:</strong> UN</span>
            <span class="RvlUnit"><strong>Vl. Unit.:</strong> 12,45</span>
          </td>
          <td><span class="valor">24,90</span></td>
        </tr></table>
      ''');

      expect(items, hasLength(1));
      expect(items.single.name, 'CAFÉ TORRADO 500G');
      expect(items.single.qty, 2);
      expect(items.single.price, 12.45);
    });
  });

  group('ReceiptQrService portal verification', () {
    test('reconhece a página de reCAPTCHA devolvida pela SEF/MG', () {
      expect(
        ReceiptQrService.requiresInteractivePortalForTesting(
          '<div class="g-recaptcha"></div>'
          '<p>passe por ele para prosseguir com a solicitação de consulta.</p>',
        ),
        isTrue,
      );
    });

    test('não confunde uma nota carregada com página de validação', () {
      expect(
        ReceiptQrService.requiresInteractivePortalForTesting(
          '<div>ARROZ (Código: 10) Qtde total de ítens: 1</div>',
        ),
        isFalse,
      );
    });
  });
}
