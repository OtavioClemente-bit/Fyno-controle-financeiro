import 'dart:io';

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; // InputImage
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;

import 'receipt_item_draft.dart';

/// QR -> portal -> extrai itens (nome + qtd + unidade + preço unitário).
///
/// Por que a QTD vinha vazia?
/// Alguns portais (incl. portalnfce) podem renderizar a quantidade como:
/// - célula "Qtde total de itens" + próxima célula "1.0000" (sem ":")
/// - OU só a célula "1.0000" (sem label)
///
/// Este parser tenta, em ordem:
/// 1) por label no texto concatenado (com ":" opcional)
/// 2) por sequência de células: encontra "Qtde/Qtd/Quantidade" e lê número do mesmo cell ou do próximo
/// 3) heurística: pega números "puros" (ex.: 1.0000 / 1,2500) e escolhe o mais provável
///
/// Se AINDA assim não achar QTD, ele usa 1.0000 como default (para não vir em branco).
class ReceiptQrService {
  // ===================== QR =====================

  static Future<String?> scanQrFromImagePath(String imagePath) async {
    final f = File(imagePath);
    if (!await f.exists()) return null;

    final scanner = BarcodeScanner(formats: const [BarcodeFormat.qrCode]);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final codes = await scanner.processImage(input);
      if (codes.isEmpty) return null;

      final raw = codes.first.rawValue?.trim();
      if (raw == null || raw.isEmpty) return null;

      return raw.replaceAll('\n', '').trim();
    } finally {
      await scanner.close();
    }
  }

  // ===================== Fluxo completo =====================

  static Future<List<ReceiptItemDraft>> extractItemsViaQr(
    String imagePath,
  ) async {
    final raw = await scanQrFromImagePath(imagePath);
    if (raw == null) {
      print('[ReceiptQr] QR não encontrado na imagem.');
      return const <ReceiptItemDraft>[];
    }

    // URLs do portal têm "p=...|3|1". Encode para não quebrar o request.
    final safe = Uri.encodeFull(raw);
    final uri = Uri.tryParse(safe);

    print('[ReceiptQr] QR raw : $raw');
    print('[ReceiptQr] QR safe: $safe');

    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      print('[ReceiptQr] QR não é URL válida.');
      return const <ReceiptItemDraft>[];
    }

    return _fetchAndParse(uri);
  }

  static Future<List<ReceiptItemDraft>> _fetchAndParse(Uri uri) async {
    try {
      final resp = await http.get(
        uri,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Android) Flutter',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
        },
      );

      print(
        '[ReceiptQr] HTTP ${resp.statusCode} (${resp.bodyBytes.length} bytes)',
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return const <ReceiptItemDraft>[];
      }

      final items = _parseItemsFromHtml(resp.body);
      print('[ReceiptQr] Itens extraídos: ${items.length}');
      return items;
    } catch (e) {
      print('[ReceiptQr] Erro ao baixar página: $e');
      return const <ReceiptItemDraft>[];
    }
  }

  // ===================== Parse HTML =====================

  static List<ReceiptItemDraft> _parseItemsFromHtml(String htmlText) {
    final doc = html.parse(htmlText);

    // 0) Portal NFC-e SEF/MG (portalsped.fazenda.mg.gov.br) costuma listar itens
    // em blocos de texto (sem tabela). Aqui extraímos quantidade e VALOR TOTAL
    // e então calculamos o valor unitário (total / quantidade).
    final portalText = doc.body?.text ?? '';
    final mgItems = _parsePortalSpedMg(portalText);
    if (mgItems.isNotEmpty) return mgItems;

    // Preferencial: tabela (tr/td)
    final out = <ReceiptItemDraft>[];

    for (final tr in doc.querySelectorAll('tr')) {
      final tds = tr.querySelectorAll('td');
      if (tds.isEmpty) continue;

      final cells = tds
          .map((e) => _cleanCell(e.text))
          .where((e) => e.isNotEmpty)
          .toList();
      if (cells.isEmpty) continue;

      final name = _cleanName(cells.first);
      if (!_looksLikeItemName(name)) continue;

      final joined = cells.join('  ');

      // TOTAL
      double? total =
          _tryParseTotalByLabel(joined) ?? _tryGuessTotalFromCells(cells);
      if (total == null) continue;

      // UNIT
      final unit =
          _tryParseUnitByLabel(joined) ?? _tryGuessUnitFromCells(cells);

      // QTY (ordem é importante)
      double? qty = _tryParseQtyByLabel(joined);
      qty ??= _tryParseQtyFromCellsSequence(cells);
      qty ??= _tryGuessQtyFromCells(cells);

      // Se ainda não achou, assume 1.0000 para não ficar em branco.
      qty ??= 1.0;

      final unitPrice = _calcUnitPrice(total, qty);

      // Debug útil (principalmente quando o portal muda o HTML)
      // print('[ReceiptQr] CELLS("$name"): $cells');
      print(
        '[ReceiptQr] ITEM: "$name" | qty=$qty | unit=${unit ?? "null"} | total=$total | unitPrice=$unitPrice',
      );

      out.add(
        ReceiptItemDraft(name: name, price: unitPrice, qty: qty, unit: unit),
      );
    }

    if (out.isNotEmpty) return _dedupe(out);

    // Fallback geral: texto
    final text = doc.body?.text ?? '';
    return _parseFromText(text);
  }
  // ===================== Portais específicos =====================

  /// Parser dedicado para o portal NFC-e da SEF/MG (portalsped.fazenda.mg.gov.br).
  ///
  /// O portal fornece o **valor total** do item, então calculamos:
  ///   unitPrice = total / qty
  ///
  /// Padrão comum no texto (sem tabela):
  ///   NOME DO PRODUTO
  ///   (Código: 54041) Qtde total de ítens: 1.0000 UN: PT Valor total R$: R$ 13,48
  static List<ReceiptItemDraft> _parsePortalSpedMg(String fullText) {
    if (fullText.trim().isEmpty) return const <ReceiptItemDraft>[];

    // Mantém quebras de linha (não use _cleanCell aqui, porque ela colapsa \n).
    var text = fullText.replaceAll('\u00A0', ' ');
    text = text.replaceAll('\r', '\n');
    text = text.replaceAll(RegExp(r'[\t ]+'), ' ');
    text = text.replaceAll(RegExp(r'\n+'), '\n');

    // Captura: nome -> (Código) -> Qtde total -> UN -> Valor total
    final re = RegExp(
      r'(?:^|\n)\s*([^\n]{3,}?)\s*\(\s*C[ÓO]DIGO\s*:\s*(\d+)\s*\)\s*'
      r'QTDE\s+TOTAL\s+DE\s+[ÍI]TENS\s*:?\s*'
      r'([0-9]+(?:[.,][0-9]+)?)\s*'
      r'UN\s*:\s*([^\s]+)\s*'
      r'VALOR\s+TOTAL\s+R\$\s*:?\s*R\$\s*'
      r'([0-9]+(?:[.\s][0-9]{3})*[,\.][0-9]{2})',
      caseSensitive: false,
      multiLine: true,
    );

    final out = <ReceiptItemDraft>[];

    for (final m in re.allMatches(text)) {
      final nameRaw = (m.group(1) ?? '').trim();
      final qtyRaw = (m.group(3) ?? '').trim();
      final unitRaw = (m.group(4) ?? '').trim();
      final totalRaw = (m.group(5) ?? '').trim();

      final name = _cleanName(nameRaw);
      final qty = _tryParseQtyLoose(qtyRaw);
      final total = _tryParseCurrency(totalRaw);

      if (name.isEmpty || total == null) continue;

      final q = (qty == null || qty <= 0) ? 1.0 : qty;
      final unitPrice = _calcUnitPrice(total, q);

      out.add(
        ReceiptItemDraft(
          name: name,
          price: unitPrice,
          qty: q,
          unit: unitRaw.isEmpty ? null : unitRaw,
        ),
      );
    }

    if (out.isEmpty) return const <ReceiptItemDraft>[];
    return _dedupe(out);
  }

  static double? _tryParseQtyLoose(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    // qty pode vir como 1.2500 ou 1,2500
    final v = s.replaceAll(',', '.');
    return double.tryParse(v);
  }

  static List<ReceiptItemDraft> _parseFromText(String fullText) {
    final lines = fullText
        .split('\n')
        .map((l) => _cleanCell(l))
        .where((l) => l.isNotEmpty)
        .toList();

    final out = <ReceiptItemDraft>[];
    String? pendingName;

    for (final line in lines) {
      final u = line.toUpperCase();

      if (_looksLikeItemName(line) &&
          !u.contains('QTDE') &&
          !u.contains('QTD') &&
          !u.contains('QUANT') &&
          !u.contains('VALOR TOTAL') &&
          !u.contains('UN:') &&
          !u.contains('CNPJ') &&
          !u.contains('INSCR') &&
          !u.contains('R\$')) {
        pendingName = _cleanName(line);
        continue;
      }

      if (pendingName != null &&
          (u.contains('QTDE') ||
              u.contains('QTD') ||
              u.contains('QUANT') ||
              u.contains('VALOR TOTAL') ||
              u.contains('UN:') ||
              _looksLikeCurrency(line))) {
        final qty =
            _tryParseQtyByLabel(line) ?? _tryParsePureNumber(line) ?? 1.0;
        final unit = _tryParseUnitByLabel(line);
        final total = _tryParseTotalByLabel(line) ?? _tryParseCurrency(line);

        if (total != null) {
          final unitPrice = _calcUnitPrice(total, qty);
          print(
            '[ReceiptQr] ITEM(TXT): "$pendingName" | qty=$qty | unit=${unit ?? "null"} | total=$total | unitPrice=$unitPrice',
          );

          out.add(
            ReceiptItemDraft(
              name: pendingName,
              price: unitPrice,
              qty: qty,
              unit: unit,
            ),
          );
          pendingName = null;
        }
      }
    }

    return _dedupe(out);
  }

  // ===================== QTY =====================

  static double? _tryParseQtyByLabel(String text) {
    // ":" é opcional porque alguns portais separam label e número em células distintas.
    final re = RegExp(
      r'\b(QTDE|QTD|QUANTIDADE|QUANT)\b(?:\s+TOTAL\s+DE\s+[ÍI]TENS)?\s*:?\s*([0-9]+(?:[.,][0-9]+)?)',
      caseSensitive: false,
    );
    final m = re.firstMatch(text);
    if (m == null) return null;

    var v = m.group(2)!.trim().replaceAll(',', '.');
    return double.tryParse(v);
  }

  static double? _tryParseQtyFromCellsSequence(List<String> cells) {
    // Procura uma célula com "Qtde/Qtd/Quantidade" e tenta ler o número:
    // - dentro da mesma célula
    // - ou na célula seguinte (quando está separado)
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      final u = c.toUpperCase();

      final hasLabel =
          u.contains('QTDE') || u.contains('QTD') || u.contains('QUANT');
      if (!hasLabel) continue;

      final inside = _tryParseQtyByLabel(c);
      if (inside != null) return inside;

      if (i + 1 < cells.length) {
        final next = _tryParsePureNumber(cells[i + 1]);
        if (next != null) return next;
      }
    }
    return null;
  }

  static double? _tryGuessQtyFromCells(List<String> cells) {
    // Pega candidatos que são "número puro" (ex.: 1.0000, 3,0000, 1.2500)
    final nums = <double>[];
    for (final c in cells) {
      if (_looksLikeCurrency(c)) continue;
      final n = _tryParsePureNumber(c);
      if (n != null) nums.add(n);
    }
    if (nums.isEmpty) return null;

    nums.sort((a, b) {
      int score(double x) {
        // qty comum: 1.0000, 2.0000, 3.0000 ou frações (kg): 1.2500
        if (x == 1.0) return 8;
        if (x > 0 && x <= 10) return 7;
        if (x > 10 && x <= 50) return 5;
        if (x > 50 && x <= 9999) return 1;
        return 0;
      }

      return score(b) - score(a);
    });

    return nums.first;
  }

  // ===================== UNIT / TOTAL =====================

  static String? _tryParseUnitByLabel(String text) {
    final m = RegExp(
      r'\bUN\s*:\s*([A-Z]{1,5})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    return m.group(1)!.trim();
  }

  static String? _tryGuessUnitFromCells(List<String> cells) {
    for (final c in cells) {
      final t = c.trim();
      if (t.isNotEmpty &&
          t.length <= 5 &&
          RegExp(r'^[A-Za-z]{1,5}$').hasMatch(t)) {
        final u = t.toUpperCase();
        if (u == 'R' || u == 'RS') continue;
        return u;
      }
    }
    return null;
  }

  static double? _tryParseTotalByLabel(String text) {
    final m = RegExp(
      r'VALOR\s+TOTAL[^0-9]*R\$[^0-9]*([0-9]+(?:[.\s][0-9]{3})*[,\.][0-9]{2})',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    return _tryParseCurrency(m.group(1)!);
  }

  static double? _tryGuessTotalFromCells(List<String> cells) {
    for (final c in cells.reversed) {
      final v = _tryParseCurrency(c);
      if (v != null) return v;
    }
    return null;
  }

  // ===================== Low-level parsers =====================

  static bool _looksLikeCurrency(String text) {
    final t = text.toUpperCase();
    if (t.contains('R\$')) return true;
    return RegExp(r'\d+[,\.]\d{2}').hasMatch(text);
  }

  static double? _tryParseCurrency(String text) {
    final m = RegExp(r'(-?\d{1,4}(?:[.\s]\d{3})*[,\.]\d{2})').firstMatch(text);
    if (m == null) return null;

    final orig = m.group(1)!.trim();
    var v = orig.replaceAll(' ', '');

    if (orig.contains(',')) {
      v = v.replaceAll('.', '');
      v = v.replaceAll(',', '.');
    }
    return double.tryParse(v);
  }

  static double? _tryParsePureNumber(String text) {
    final t = text.trim();
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)$').firstMatch(t);
    if (m == null) return null;
    var v = m.group(1)!.replaceAll(',', '.');
    return double.tryParse(v);
  }

  static double _calcUnitPrice(double total, double qty) {
    if (qty <= 0) return _round2(total);
    return _round2(total / qty);
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100.0;

  // ===================== Helpers =====================

  static String _cleanCell(String s) {
    var x = s.replaceAll('\u00A0', ' '); // nbsp
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }

  static bool _looksLikeItemName(String s) {
    if (s.length < 3) return false;
    final u = s.toUpperCase();
    if (u.contains('CNPJ') || u.contains('INSCR') || u.contains('CPF')) {
      return false;
    }
    if (u.contains('VALOR TOTAL') || u.contains('QTDE') || u.contains('QTD')) {
      return false;
    }
    return RegExp(r'[A-ZÀ-Ü]', caseSensitive: false).hasMatch(s);
  }

  static String _cleanName(String s) {
    var x = _cleanCell(s);
    x = x.replaceFirst(RegExp(r'^[\d\W_#]+'), '').trim();
    x = x
        .replaceAll(
          RegExp(r'\(C[ÓO]DIGO\s*:\s*\d+\)', caseSensitive: false),
          '',
        )
        .trim();
    x = x
        .replaceAll(RegExp(r'\(CODIGO\s*:\s*\d+\)', caseSensitive: false), '')
        .trim();
    return x;
  }

  static List<ReceiptItemDraft> _dedupe(List<ReceiptItemDraft> items) {
    final seen = <String>{};
    final out = <ReceiptItemDraft>[];

    for (final it in items) {
      final key =
          '${_norm(it.name)}|${it.price.toStringAsFixed(2)}|${it.qty!.toStringAsFixed(4)}|${it.unit ?? ""}';
      if (seen.add(key)) out.add(it);
    }
    return out;
  }

  static String _norm(String s) {
    var x = s.toUpperCase();
    const map = {
      'Á': 'A',
      'À': 'A',
      'Â': 'A',
      'Ã': 'A',
      'Ä': 'A',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Î': 'I',
      'Ï': 'I',
      'Ó': 'O',
      'Ò': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ö': 'O',
      'Ú': 'U',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ç': 'C',
    };
    map.forEach((k, v) => x = x.replaceAll(k, v));
    x = x.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    return x;
  }
}
