import 'dart:convert';

class ClipboardAiImportResult {
  const ClipboardAiImportResult({
    required this.namesByIndex,
    required this.ignoredEntries,
  });

  final Map<int, String> namesByIndex;
  final int ignoredEntries;
}

/// Fluxo de IA sem API: gera um pedido autocontido para qualquer assistente e
/// interpreta a resposta usando IDs estáveis, sem depender da ordem dos itens.
class ProductNameClipboardAi {
  static String buildPrompt(List<String> names) {
    final products = <Map<String, Object>>[
      for (var index = 0; index < names.length; index++)
        {'id': index + 1, 'nome_na_nota': names[index].trim()},
    ];
    const encoder = JsonEncoder.withIndent('  ');
    return '''Você é especialista em padronização de nomes de produtos brasileiros.

Reescreva cada nome abreviado de cupom fiscal como um nome real, claro e profissional, preservando marca, sabor, tipo, quantidade, peso e volume quando estiverem informados. Expanda abreviações com segurança, corrija caixa e acentuação e remova somente códigos fiscais ou internos. Não invente marca, tamanho ou característica que não esteja no texto.

Responda SOMENTE com um array JSON válido, sem Markdown e sem explicações, exatamente neste formato:
[{"id": 1, "nome": "Nome profissional"}]

Mantenha o mesmo id de cada produto. Produtos:
${encoder.convert(products)}''';
  }

  static ClipboardAiImportResult parseResponse(
    String response, {
    required int itemCount,
  }) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Cole primeiro a resposta da IA.');
    }

    final start = trimmed.indexOf('[');
    final end = trimmed.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const FormatException(
        'Não encontrei a lista JSON na resposta. Peça para a IA seguir o formato do prompt.',
      );
    }

    final decoded = jsonDecode(trimmed.substring(start, end + 1));
    if (decoded is! List) {
      throw const FormatException('A resposta não contém uma lista válida.');
    }

    final result = <int, String>{};
    var ignored = 0;
    for (final entry in decoded) {
      if (entry is! Map) {
        ignored++;
        continue;
      }
      final rawId = entry['id'];
      final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
      final name = '${entry['nome'] ?? ''}'.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      if (id == null || id < 1 || id > itemCount || name.length < 2) {
        ignored++;
        continue;
      }
      result[id - 1] = name.length > 160 ? name.substring(0, 160) : name;
    }

    if (result.isEmpty) {
      throw const FormatException(
        'Nenhum nome válido foi encontrado na resposta da IA.',
      );
    }
    return ClipboardAiImportResult(
      namesByIndex: result,
      ignoredEntries: ignored,
    );
  }
}
