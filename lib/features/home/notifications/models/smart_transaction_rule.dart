class SmartTransactionRule {
  const SmartTransactionRule({
    this.id,
    required this.merchantKey,
    required this.merchantName,
    required this.title,
    required this.category,
    required this.isIncome,
    required this.paymentMethod,
    required this.useCount,
    required this.updatedAtMs,
  });

  final int? id;
  final String merchantKey;
  final String merchantName;
  final String title;
  final String category;
  final bool isIncome;
  final String paymentMethod;
  final int useCount;
  final int updatedAtMs;

  factory SmartTransactionRule.fromMap(Map<String, Object?> map) =>
      SmartTransactionRule(
        id: map['id'] as int?,
        merchantKey: map['merchant_key'] as String,
        merchantName: map['merchant_name'] as String,
        title: map['title'] as String,
        category: map['category'] as String,
        isIncome: map['is_income'] == 1,
        paymentMethod: map['payment_method'] as String,
        useCount: (map['use_count'] as num?)?.toInt() ?? 1,
        updatedAtMs: (map['updated_at_ms'] as num).toInt(),
      );
}

class MerchantIdentity {
  const MerchantIdentity({required this.key, required this.name});

  final String key;
  final String name;

  static MerchantIdentity? extract(String title, String text) {
    final source = '$title $text'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (source.isEmpty) return null;
    final patterns = <RegExp>[
      RegExp(
        r'(?:compra|pagamento)(?:\s+aprovad[ao])?\s+(?:em|no|na)\s+([^,.•|]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:pix|transfer[eê]ncia)\s+(?:para|de)\s+([^,.•|]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:estabelecimento|favorecido|recebedor)\s*:?\s*([^,.•|]+)',
        caseSensitive: false,
      ),
    ];
    String? candidate;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      if (match != null) {
        candidate = match.group(1)?.trim();
        break;
      }
    }
    candidate ??= source;
    candidate = candidate
        .replaceAll(RegExp(r'R\$\s*[\d.,]+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b\d{1,2}[:/]\d{1,2}(?:[/:]\d{2,4})?\b'), ' ')
        .replaceAll(
          RegExp(
            r'\b(aprovad[ao]|realizad[ao]|recebid[ao]|valor|compra|pix|pagamento|cart[aã]o|cr[eé]dito|d[eé]bito)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (candidate.length < 3) return null;
    if (candidate.length > 48) candidate = candidate.substring(0, 48).trim();
    final key = normalize(candidate);
    return key.length < 3 ? null : MerchantIdentity(key: key, name: candidate);
  }

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàãâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòõôö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
