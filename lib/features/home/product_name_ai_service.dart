import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'product_name_formatter.dart';

enum ProductNameEnhancementOrigin { local, ai }

class ProductNameEnhancement {
  final int index;
  final String professionalName;
  final double confidence;
  final ProductNameEnhancementOrigin origin;

  const ProductNameEnhancement({
    required this.index,
    required this.professionalName,
    required this.confidence,
    required this.origin,
  });
}

class ProductNameEnhancementBatch {
  final List<ProductNameEnhancement> products;
  final bool usedAi;
  final String message;

  const ProductNameEnhancementBatch({
    required this.products,
    required this.usedAi,
    required this.message,
  });
}

/// Cliente do backend seguro de nomes de produtos.
///
/// Configure apenas a URL do servidor no build:
/// --dart-define=FYNO_PRODUCT_AI_ENDPOINT=https://seu-servidor/normalize-products
///
/// A chave da OpenAI jamais deve ser incluída aqui ou em outro arquivo do app.
class ProductNameAiService {
  static const _endpoint = String.fromEnvironment('FYNO_PRODUCT_AI_ENDPOINT');
  static const _maxProducts = 50;

  static bool get isAiConfigured => _safeEndpoint() != null;

  static Future<ProductNameEnhancementBatch> enhance(List<String> names) async {
    final limited = names.take(_maxProducts).toList(growable: false);
    final local = _localEnhancements(limited);
    final endpoint = _safeEndpoint();
    if (endpoint == null || limited.isEmpty) {
      return ProductNameEnhancementBatch(
        products: local,
        usedAi: false,
        message: limited.isEmpty
            ? 'Nenhum produto para revisar.'
            : 'Nomes padronizados no próprio aparelho.',
      );
    }

    try {
      final response = await http
          .post(
            endpoint,
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'locale': 'pt-BR',
              'products': [
                for (var i = 0; i < limited.length; i++)
                  {'index': i, 'raw_name': limited[i]},
              ],
            }),
          )
          .timeout(const Duration(seconds: 18));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallback(local);
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return _fallback(local);
      final rows = decoded['products'];
      if (rows is! List) return _fallback(local);

      final byIndex = <int, ProductNameEnhancement>{};
      for (final row in rows) {
        if (row is! Map) continue;
        final index = (row['index'] as num?)?.toInt();
        final proposed = (row['professional_name'] as String?)?.trim() ?? '';
        final confidence = (row['confidence'] as num?)?.toDouble() ?? .5;
        if (index == null || index < 0 || index >= limited.length) continue;
        final safeName = _safeName(proposed);
        if (safeName == null) continue;
        byIndex[index] = ProductNameEnhancement(
          index: index,
          professionalName: safeName,
          confidence: confidence.clamp(0, 1),
          origin: ProductNameEnhancementOrigin.ai,
        );
      }

      final merged = <ProductNameEnhancement>[];
      for (var i = 0; i < limited.length; i++) {
        merged.add(byIndex[i] ?? local[i]);
      }
      return ProductNameEnhancementBatch(
        products: merged,
        usedAi: byIndex.isNotEmpty,
        message: byIndex.isNotEmpty
            ? 'Nomes revisados pela IA. Confira antes de salvar.'
            : 'Nomes padronizados no próprio aparelho.',
      );
    } on TimeoutException {
      return _fallback(local);
    } on FormatException {
      return _fallback(local);
    } catch (_) {
      return _fallback(local);
    }
  }

  static Uri? _safeEndpoint() {
    final uri = Uri.tryParse(_endpoint.trim());
    if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
    if (uri.userInfo.isNotEmpty) return null;
    return uri;
  }

  static List<ProductNameEnhancement> _localEnhancements(List<String> names) {
    return [
      for (var i = 0; i < names.length; i++)
        ProductNameEnhancement(
          index: i,
          professionalName: formatProductNameLocally(names[i]),
          confidence: .7,
          origin: ProductNameEnhancementOrigin.local,
        ),
    ];
  }

  static ProductNameEnhancementBatch _fallback(
    List<ProductNameEnhancement> local,
  ) {
    return ProductNameEnhancementBatch(
      products: local,
      usedAi: false,
      message: 'A IA está indisponível. Usei a padronização do aparelho.',
    );
  }

  static String? _safeName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length < 2 || cleaned.length > 120) return null;
    return cleaned;
  }
}
