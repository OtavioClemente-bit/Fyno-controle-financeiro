/// Melhora nomes típicos de NFC-e sem internet e sem alterar o significado.
///
/// Esta camada é intencionalmente conservadora: expande apenas abreviações
/// comuns e formata unidades. Casos ambíguos continuam disponíveis para a
/// revisão por IA ou edição manual.
String formatProductNameLocally(String input) {
  var value = input.trim();
  if (value.isEmpty) return value;

  value = value.replaceAll(RegExp(r'\s+'), ' ');
  value = value.replaceFirst(RegExp(r'^\s*\d+\s*[)\-.]?\s*'), '');
  value = value.replaceAll(
    RegExp(r'\(\s*C[ÓO]D(?:IGO)?\s*:\s*\d+\s*\)', caseSensitive: false),
    '',
  );
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Junta e normaliza medidas antes de tratar as palavras.
  value = value.replaceAllMapped(
    RegExp(r'\b(\d+(?:[.,]\d+)?)\s*(ML|MG|KG|GR|G|L)\b', caseSensitive: false),
    (match) => '${match.group(1)} ${_unit(match.group(2)!)}',
  );

  const expansions = <String, String>{
    'REFR': 'Refrigerante',
    'REF': 'Refrigerante',
    'BISC': 'Biscoito',
    'BOL': 'Bolacha',
    'RECH': 'Recheado',
    'CHOC': 'Chocolate',
    'TRAD': 'Tradicional',
    'INT': 'Integral',
    'DESN': 'Desnatado',
    'SEMID': 'Semidesnatado',
    'ACUC': 'Açúcar',
    'T1': 'Tipo 1',
    'T2': 'Tipo 2',
    'PCT': 'Pacote',
    'PCTE': 'Pacote',
    'CX': 'Caixa',
    'GFA': 'Garrafa',
    'GF': 'Garrafa',
    'LT': 'Lata',
    'LATA': 'Lata',
    'UN': 'Unidade',
    'UND': 'Unidade',
  };

  final words = value.split(' ');
  final formatted = <String>[];
  for (final rawWord in words) {
    if (rawWord.isEmpty) continue;
    final lookup = _withoutDiacritics(rawWord).toUpperCase();
    final expanded = expansions[lookup];
    if (expanded != null) {
      formatted.add(expanded);
      continue;
    }
    formatted.add(_formatToken(rawWord, formatted.isEmpty));
  }

  value = formatted.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  value = value.replaceAll(
    RegExp(r'\bCoca Cola\b', caseSensitive: false),
    'Coca-Cola',
  );
  value = value.replaceAll(
    RegExp(r'\bNescafe\b', caseSensitive: false),
    'Nescafé',
  );
  value = value.replaceAll(
    RegExp(r'\bNestle\b', caseSensitive: false),
    'Nestlé',
  );
  return value;
}

String _unit(String raw) {
  switch (raw.toUpperCase()) {
    case 'ML':
      return 'ml';
    case 'MG':
      return 'mg';
    case 'KG':
      return 'kg';
    case 'GR':
    case 'G':
      return 'g';
    default:
      return 'L';
  }
}

String _formatToken(String token, bool first) {
  final upper = token.toUpperCase();
  if (const {'ML', 'MG', 'KG', 'G'}.contains(upper)) {
    return upper.toLowerCase();
  }
  const keepUpper = <String>{'UHT', 'PET', 'ZERO', 'DIET', 'LIGHT', 'EXTRA'};
  if (keepUpper.contains(upper)) return upper;
  if (RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(token)) return token;
  if (RegExp(r'^\d+(?:[.,]\d+)?(?:ml|mg|kg|g|L)$').hasMatch(token)) {
    return token;
  }

  const lowerWords = <String>{'DE', 'DA', 'DO', 'DAS', 'DOS', 'COM', 'E'};
  if (!first && lowerWords.contains(upper)) return upper.toLowerCase();
  if (token.length == 1) return upper;
  return '${token[0].toUpperCase()}${token.substring(1).toLowerCase()}';
}

String _withoutDiacritics(String value) {
  const from = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const to = 'AAAAAEEEEIIIIOOOOOUUUUC';
  var output = value.toUpperCase();
  for (var i = 0; i < from.length; i++) {
    output = output.replaceAll(from[i], to[i]);
  }
  return output;
}
