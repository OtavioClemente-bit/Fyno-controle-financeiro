import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_item_draft.dart';
import 'normalize_product.dart';

class ReceiptOcrService {
  /// Extrai itens do texto reconhecido (OCR) de um comprovante.
  /// Observação: é heurístico. Sempre use uma tela de conferência.
  static Future<List<ReceiptItemDraft>> extractFromImagePath(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return <ReceiptItemDraft>[];

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);
      final text = recognized.text;
      return _parseItemsFromText(text);
    } finally {
      await recognizer.close();
    }
  }

  static List<ReceiptItemDraft> _parseItemsFromText(String fullText) {
    final lines = fullText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final out = <ReceiptItemDraft>[];

    // Matches a money value at end of line: 12,34 or 1.234,56
    final moneyAtEnd = RegExp(r'(-?\d{1,4}(?:[.,]\d{3})*[.,]\d{2})\s*$');

    bool looksLikeTotals(String s) {
      final u = normalizeProductName(s);
      const bad = [
        'TOTAL',
        'SUBTOTAL',
        'TROCO',
        'DESCONTO',
        'VALOR',
        'PAGAMENTO',
        'FORMA PAGAMENTO',
        'CNPJ',
        'CPF',
        'IE',
        'COO',
        'CCF',
        'OPERADOR',
        'CAIXA',
        'OBRIGADO',
        'AUTORIZACAO',
        'APROVACAO',
        'TRANSACAO',
        'NSU',
        'TEF',
        'CREDITO',
        'DEBITO',
        'PIX',
        'BANDEIRA',
        'VISA',
        'MASTERCARD',
        'ELO',
      ];
      for (final b in bad) {
        if (u.contains(b)) return true;
      }
      return false;
    }

    double? parseMoney(String raw) {
      // raw may be 1.234,56 or 1234.56
      var s = raw.trim();
      // If comma is decimal separator, remove thousand dots.
      if (s.contains(',') && !s.contains('.')) {
        s = s.replaceAll('.', '');
        s = s.replaceAll(',', '.');
      } else if (s.contains(',') && s.contains('.')) {
        // Decide decimal separator by last occurrence
        final lastComma = s.lastIndexOf(',');
        final lastDot = s.lastIndexOf('.');
        if (lastComma > lastDot) {
          s = s.replaceAll('.', '');
          s = s.replaceAll(',', '.');
        } else {
          s = s.replaceAll(',', '');
        }
      }
      return double.tryParse(s);
    }

    for (final line in lines) {
      if (looksLikeTotals(line)) continue;

      final m = moneyAtEnd.firstMatch(line);
      if (m == null) continue;

      final priceRaw = m.group(1) ?? '';
      final price = parseMoney(priceRaw);
      if (price == null) continue;

      var name = line.substring(0, m.start).trim();
      name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
      name = name.replaceAll(RegExp(r'\bR\$\b'), '').trim();

      // Remove trailing separators
      name = name.replaceAll(RegExp(r'[-:]+$'), '').trim();

      // Remove obvious quantity prefixes like "2 UN" (optional)
      // Keep as part of name for now — user can adjust in conferência.

      if (name.length < 3) continue;

      out.add(ReceiptItemDraft(name: name, price: price));
    }

    // Small cleanup: remove duplicates that are exactly the same
    final seen = <String>{};
    final cleaned = <ReceiptItemDraft>[];
    for (final it in out) {
      final key = '${normalizeProductName(it.name)}|${it.price.toStringAsFixed(2)}';
      if (seen.add(key)) cleaned.add(it);
    }
    return cleaned;
  }
}
