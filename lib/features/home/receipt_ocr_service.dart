import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'normalize_product.dart';
import 'receipt_item_draft.dart';

class ReceiptOcrService {
  static final _moneyPattern = RegExp(
    r'(?:R\$\s*)?(-?\d{1,6}(?:\.\d{3})*,\d{2}|-?\d{1,6}[,.]\d{2})(?!\d)',
    caseSensitive: false,
  );
  static final _quantityLabelPattern = RegExp(
    r'\b(?:QTDE?|QTD|QUANT(?:IDADE)?)\.?\s*(?:TOTAL\s+DE\s+[ÍI]TENS?)?\s*[:=]?\s*(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  );
  static final _multiplicationPattern = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*(UN|UND|UNID|KG|G|L|LT|ML|PCT|CX)?\s*[X@]\s*(?=(?:R\$\s*)?\d)',
    caseSensitive: false,
  );
  static final _quantityUnitPattern = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s+(UN|UND|UNID|KG)\b',
    caseSensitive: false,
  );
  static final _unitPriceLabelPattern = RegExp(
    r'(?:VL|VLR|VALOR|PRE[ÇC]O)\.?\s*UNIT(?:[ÁA]RIO)?[^0-9]*(?:R\$\s*)?(-?\d{1,6}(?:\.\d{3})*,\d{2}|-?\d{1,6}[,.]\d{2})(?!\d)',
    caseSensitive: false,
  );
  static final _totalLabelPattern = RegExp(
    r'(?:VL|VLR|VALOR)\.?\s*TOTAL[^0-9]*(?:R\$\s*)?(-?\d{1,6}(?:\.\d{3})*,\d{2}|-?\d{1,6}[,.]\d{2})(?!\d)',
    caseSensitive: false,
  );

  /// Extrai itens e converte o total da linha em preço unitário sempre que a
  /// quantidade estiver disponível.
  static Future<List<ReceiptItemDraft>> extractFromImagePath(
    String imagePath,
  ) async {
    final file = File(imagePath);
    if (!await file.exists()) return <ReceiptItemDraft>[];

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);
      return parseRecognizedText(recognized.text);
    } finally {
      await recognizer.close();
    }
  }

  /// Público para testar os formatos encontrados em notas reais.
  static List<ReceiptItemDraft> parseRecognizedText(String fullText) {
    final lines = fullText
        .split('\n')
        .map(_cleanLine)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    final items = <ReceiptItemDraft>[];
    String? pendingName;

    for (final line in lines) {
      final moneyMatches = _moneyPattern.allMatches(line).toList();
      if (moneyMatches.isEmpty) {
        if (_looksLikeProductName(line)) pendingName = _cleanName(line);
        continue;
      }

      if (_isGrandTotalLine(line)) {
        pendingName = null;
        continue;
      }

      final quantityData = _readQuantity(
        line,
        hasPendingName: pendingName != null,
        moneyCount: moneyMatches.length,
      );
      final quantity = quantityData.quantity ?? 1;
      final total =
          _readLabeledMoney(line, _totalLabelPattern) ??
          _parseMoney(moneyMatches.last.group(1)!);
      if (total == null || total <= 0) continue;

      final explicitUnitPrice =
          _readLabeledMoney(line, _unitPriceLabelPattern) ??
          _readPriceAfterMultiplication(line) ??
          _findConsistentUnitPrice(
            moneyMatches,
            quantity: quantity,
            total: total,
          );

      final inlineName = _extractInlineName(line, moneyMatches.first.start);
      final name = (pendingName?.trim().isNotEmpty ?? false)
          ? pendingName!
          : inlineName;
      if (name.length < 3 || !_hasLetters(name)) continue;

      final item = explicitUnitPrice != null
          ? ReceiptItemDraft.fromUnitPrice(
              name: name,
              unitPrice: explicitUnitPrice,
              qty: quantity,
              unit: quantityData.unit,
              lineTotal: total,
            )
          : ReceiptItemDraft.fromLineTotal(
              name: name,
              total: total,
              qty: quantity,
              unit: quantityData.unit,
            );
      items.add(item);
      pendingName = null;
    }

    return _dedupe(items);
  }

  static _QuantityData _readQuantity(
    String line, {
    required bool hasPendingName,
    required int moneyCount,
  }) {
    final labeled = _quantityLabelPattern.firstMatch(line);
    if (labeled != null) {
      return _QuantityData(
        quantity: _parseQuantity(labeled.group(1)),
        unit: _readUnitNearQuantity(line, labeled.end),
      );
    }

    final multiplied = _multiplicationPattern.firstMatch(line);
    if (multiplied != null) {
      return _QuantityData(
        quantity: _parseQuantity(multiplied.group(1)),
        unit: multiplied.group(2)?.toUpperCase(),
      );
    }

    final unitMatches = _quantityUnitPattern.allMatches(line).toList();
    final hasUnambiguousUnit = unitMatches.any(
      (match) => (match.group(2) ?? '').toUpperCase().startsWith('UN'),
    );
    if (unitMatches.isNotEmpty &&
        (hasUnambiguousUnit || hasPendingName || moneyCount >= 2)) {
      final match = unitMatches.last;
      return _QuantityData(
        quantity: _parseQuantity(match.group(1)),
        unit: match.group(2)?.toUpperCase(),
      );
    }
    return const _QuantityData();
  }

  static String? _readUnitNearQuantity(String line, int start) {
    final match = RegExp(
      r'^\s*(?:UN\s*[:=]\s*)?(UN|UND|UNID|KG|G|L|LT|ML|PCT|CX)\b',
      caseSensitive: false,
    ).firstMatch(line.substring(start));
    return match?.group(1)?.toUpperCase();
  }

  static double? _readLabeledMoney(String line, RegExp pattern) {
    final match = pattern.firstMatch(line);
    return match == null ? null : _parseMoney(match.group(1));
  }

  static double? _readPriceAfterMultiplication(String line) {
    final multiplication = _multiplicationPattern.firstMatch(line);
    if (multiplication == null) return null;
    final money = _moneyPattern.firstMatch(line.substring(multiplication.end));
    return money == null ? null : _parseMoney(money.group(1));
  }

  static double? _findConsistentUnitPrice(
    List<RegExpMatch> moneyMatches, {
    required double quantity,
    required double total,
  }) {
    if (quantity <= 0 || moneyMatches.length < 2) return null;
    for (final match in moneyMatches.reversed.skip(1)) {
      final candidate = _parseMoney(match.group(1));
      if (candidate == null) continue;
      if ((candidate * quantity - total).abs() <= .06) return candidate;
    }
    return null;
  }

  static String _extractInlineName(String line, int firstMoneyStart) {
    var cut = firstMoneyStart;
    for (final pattern in [
      _quantityLabelPattern,
      _multiplicationPattern,
      _quantityUnitPattern,
      _unitPriceLabelPattern,
      _totalLabelPattern,
    ]) {
      final match = pattern.firstMatch(line);
      if (match != null && match.start < cut) cut = match.start;
    }
    return _cleanName(line.substring(0, cut));
  }

  static String _cleanName(String value) {
    var name = _cleanLine(value);
    name = name.replaceFirst(RegExp(r'^\d{1,3}\s*[)\-.]\s*'), '');
    name = name.replaceFirst(RegExp(r'^\d{8,14}\s+'), '');
    return name.replaceAll(RegExp(r'[-:=]+$'), '').trim();
  }

  static bool _looksLikeProductName(String line) {
    if (line.length < 3 || !_hasLetters(line)) return false;
    final normalized = normalizeProductName(line);
    const blocked = [
      'CNPJ',
      'CPF',
      'INSCRICAO',
      'DOCUMENTO AUXILIAR',
      'CHAVE DE ACESSO',
      'CONSUMIDOR',
      'PAGAMENTO',
      'FORMA DE PAGAMENTO',
      'OPERADOR',
      'CAIXA',
      'AUTORIZACAO',
      'TRANSACAO',
      'OBRIGADO',
    ];
    if (blocked.any(normalized.contains)) return false;
    return !_isGrandTotalLine(line);
  }

  static bool _isGrandTotalLine(String line) => RegExp(
    r'^(TOTAL(?: A PAGAR)?|SUBTOTAL|TROCO|DESCONTO|VALOR A PAGAR|VALOR PAGO)\b',
  ).hasMatch(normalizeProductName(line));

  static bool _hasLetters(String value) =>
      RegExp(r'[A-ZÁÀÂÃÉÈÊÍÌÎÓÒÔÕÚÙÛÇ]', caseSensitive: false).hasMatch(value);

  static double? _parseQuantity(String? raw) {
    if (raw == null) return null;
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    return value == null || !value.isFinite || value <= 0 ? null : value;
  }

  static double? _parseMoney(String? raw) {
    if (raw == null) return null;
    final original = raw.trim().replaceAll(' ', '');
    final normalized = original.contains(',')
        ? original.replaceAll('.', '').replaceAll(',', '.')
        : original;
    return double.tryParse(normalized);
  }

  static String _cleanLine(String value) =>
      value.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<ReceiptItemDraft> _dedupe(List<ReceiptItemDraft> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(
          '${normalizeProductName(item.name)}|'
          '${item.effectiveQty.toStringAsFixed(4)}|'
          '${item.effectiveLineTotal.toStringAsFixed(2)}',
        ))
          item,
    ];
  }
}

class _QuantityData {
  final double? quantity;
  final String? unit;

  const _QuantityData({this.quantity, this.unit});
}
