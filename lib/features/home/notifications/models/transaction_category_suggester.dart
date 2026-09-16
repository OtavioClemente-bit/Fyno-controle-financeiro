import 'dart:math' as math;

/// Sugestão local e explicável. Nenhum texto bancário sai do aparelho.
class TransactionCategorySuggestion {
  const TransactionCategorySuggestion({
    required this.category,
    required this.confidence,
  });

  final String category;
  final double confidence;
}

class TransactionCategorySuggester {
  static TransactionCategorySuggestion suggest({
    required String text,
    required bool? isIncome,
  }) {
    final normalized = _normalize(text);
    final rules = isIncome == true ? _incomeRules : _expenseRules;

    String fallback = isIncome == true ? 'Outros' : 'Outros';
    String? bestCategory;
    var bestScore = 0;
    var bestRuleSize = 1;

    for (final entry in rules.entries) {
      var score = 0;
      for (final term in entry.value) {
        if (_containsTerm(normalized, term)) {
          score++;
          bestRuleSize = math.max(bestRuleSize, term.split(' ').length);
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestCategory = entry.key;
      }
    }

    if (bestCategory == null) {
      return TransactionCategorySuggestion(
        category: fallback,
        confidence: isIncome == null ? .35 : .45,
      );
    }
    return TransactionCategorySuggestion(
      category: bestCategory,
      confidence: math.min(
        .96,
        .68 + (bestScore - 1) * .1 + bestRuleSize * .02,
      ),
    );
  }

  static const _expenseRules = <String, List<String>>{
    'Mercado': [
      'mercado',
      'supermercado',
      'atacadao',
      'assai',
      'carrefour',
      'extra',
      'pao de acucar',
      'hortifruti',
      'acougue',
    ],
    'Alimentação': [
      'restaurante',
      'lanchonete',
      'ifood',
      'rappi',
      'padaria',
      'pizzaria',
      'hamburguer',
      'burger',
      'mcdonald',
      'cafeteria',
    ],
    'Combustível': [
      'posto',
      'combustivel',
      'gasolina',
      'etanol',
      'diesel',
      'shell',
      'ipiranga',
      'petrobras',
    ],
    'Transporte': [
      'uber',
      '99app',
      '99 pop',
      'taxi',
      'pedagio',
      'estacionamento',
      'metro',
      'onibus',
      'passagem',
    ],
    'Contas': [
      'energia',
      'eletricidade',
      'internet',
      'telefone',
      'celular',
      'agua',
      'condominio',
      'fatura',
      'assinatura',
    ],
    'Casa': [
      'aluguel',
      'material de construcao',
      'leroy',
      'mobly',
      'moveis',
      'eletrodomestico',
    ],
    'Saúde': [
      'farmacia',
      'drogaria',
      'hospital',
      'clinica',
      'consulta',
      'laboratorio',
      'dentista',
      'medicamento',
    ],
    'Educação': [
      'escola',
      'faculdade',
      'curso',
      'livraria',
      'papelaria',
      'udemy',
      'mensalidade escolar',
    ],
    'Lazer': [
      'cinema',
      'teatro',
      'show',
      'netflix',
      'spotify',
      'steam',
      'playstation',
      'parque',
    ],
    'Viagem': [
      'hotel',
      'pousada',
      'airbnb',
      'azul linhas',
      'latam',
      'gol linhas',
      'booking',
      'decolar',
    ],
    'Investimento': [
      'corretora',
      'investimento',
      'tesouro direto',
      'aplicacao',
      'cdb',
      'acao',
      'fundo imobiliario',
    ],
  };

  static const _incomeRules = <String, List<String>>{
    'Salário': ['salario', 'folha de pagamento', 'pagamento salarial'],
    'Rendimentos': [
      'rendimento',
      'dividendo',
      'juros',
      'cashback',
      'provento',
      'resgate',
    ],
    'Vendas': ['venda', 'produto vendido', 'marketplace'],
    'Freelance': ['freelance', 'servico prestado', 'honorario'],
  };

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàãâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòõôö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _containsTerm(String normalized, String term) {
    return RegExp(
      '(^|[^a-z0-9])${RegExp.escape(term)}([^a-z0-9]|\$)',
    ).hasMatch(normalized);
  }
}
