import 'dart:async';

import 'package:flutter/material.dart';

import 'package:controle_financeiro/core/db/app_db.dart';

/// Acesso direto ao SQLite para o histórico de preços (tabela `receipt_items`).
/// Mantém a tela independente de repositórios externos.
class _ReceiptItemsRepo {
  static const String _table = 'receipt_items';

  /// Sugestões agrupadas por produto (norm_name), com contagem e último preço/data.
  ///
  /// - Se `query` estiver vazio, retorna os produtos mais recentes (top).
  /// - Se `query` tiver texto, filtra por raw_name ou norm_name (case-insensitive).
  static Future<List<Map<String, Object?>>> searchProducts(String query) async {
    final db = await AppDb.instance;
    final q = query.trim();

    if (q.isEmpty) {
      final rows = await db.rawQuery(r'''
      SELECT
        norm_name,
        MAX(raw_name) AS display_name,
        COUNT(*) AS count,
        MAX(date_ms) AS last_date,
        (
          SELECT price
          FROM receipt_items r2
          WHERE r2.norm_name = r1.norm_name
          ORDER BY date_ms DESC, id DESC
          LIMIT 1
        ) AS last_price
      FROM receipt_items r1
      GROUP BY norm_name
      ORDER BY last_date DESC
      LIMIT 120
    ''');

      return rows.cast<Map<String, Object?>>();
    }

    final like = '%$q%';
    // Busca por nome bruto OU normalizado (case-insensitive)
    final rows = await db.rawQuery(
      r'''
    SELECT
      norm_name,
      MAX(raw_name) AS display_name,
      COUNT(*) AS count,
      MAX(date_ms) AS last_date,
      (
        SELECT price
        FROM receipt_items r2
        WHERE r2.norm_name = r1.norm_name
        ORDER BY date_ms DESC, id DESC
        LIMIT 1
      ) AS last_price
    FROM receipt_items r1
    WHERE raw_name LIKE ? COLLATE NOCASE
       OR norm_name LIKE ? COLLATE NOCASE
    GROUP BY norm_name
    ORDER BY last_date DESC
    LIMIT 120
  ''',
      [like, like],
    );

    return rows.cast<Map<String, Object?>>();
  }

  /// Histórico completo de um produto (ordenado do mais recente pro mais antigo).
  static Future<List<Map<String, Object?>>> getHistoryByNormName(
    String normName,
  ) async {
    final db = await AppDb.instance;

    final rows = await db.query(
      _table,
      columns: [
        'id',
        'tx_id',
        'date_ms',
        'raw_name',
        'norm_name',
        'price',
        'qty',
        'unit',
        'market',
      ],
      where: 'norm_name = ?',
      whereArgs: [normName],
      orderBy: 'date_ms DESC, id DESC',
      limit: 250,
    );

    return rows.cast<Map<String, Object?>>();
  }

  /// Atualiza o preço (coluna `price`) de um item pelo `id`.
  static Future<void> updateReceiptItemPrice({
    required int itemId,
    required double newPrice,
  }) async {
    final db = await AppDb.instance;
    final rows = await db.update(
      _table,
      {'price': newPrice},
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (rows == 0) {
      throw Exception('Nenhum item atualizado (id=$itemId).');
    }
  }

  /// Exclui um item do histórico pelo `id`.
  static Future<void> deleteReceiptItem({required int itemId}) async {
    final db = await AppDb.instance;
    final rows = await db.delete(_table, where: 'id = ?', whereArgs: [itemId]);
    if (rows == 0) {
      throw Exception('Nenhum item excluído (id=$itemId).');
    }
  }

  /// Insere um item manualmente na tabela `receipt_items`.
  /// Útil para registrar preços mesmo sem ler um cupom.
  static Future<int> insertReceiptItem({
    required String rawName,
    required String normName,
    required double price,
    required int dateMs,
    double? qty,
    String? unit,
    String? market,
    int txId = 0,
  }) async {
    final db = await AppDb.instance;

    final values = <String, Object?>{
      'tx_id': txId,
      'date_ms': dateMs,
      'raw_name': rawName,
      'norm_name': normName,
      'price': price,
      'qty': qty,
      'unit': (unit ?? '').trim().isEmpty ? null : unit!.trim(),
      'market': (market ?? '').trim().isEmpty ? 'Manual' : market!.trim(),
    };

    return db.insert(_table, values);
  }
}

/// Página para consultar histórico de preços de produtos capturados em cupons/itens.
/// - Busca com debounce e sugestões agrupadas por produto
/// - Histórico com ações: editar preço e excluir item (persistindo no DB)
///
/// Página para consultar histórico de preços de produtos capturados em cupons/itens.
/// - Busca com debounce e sugestões agrupadas por produto
/// - Histórico com ações: editar preço e excluir item (persistindo no SQLite)
///
/// Obs: esta tela acessa diretamente a tabela `receipt_items` via AppDb.
class ProductPricesPage extends StatefulWidget {
  const ProductPricesPage({super.key});

  @override
  State<ProductPricesPage> createState() => _ProductPricesPageState();
}

class _ProductPricesPageState extends State<ProductPricesPage> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollCtrl = ScrollController();

  Timer? _debounce;
  bool _loading = false;
  String? _error;

  String? _selectedNorm;
  String _selectedDisplay = '';

  List<Map<String, Object?>> _suggestions = const [];
  List<Map<String, Object?>> _history = const [];

  @override
  void initState() {
    super.initState();
    // Carrega produtos automaticamente (sem precisar pesquisar).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _search('');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      final q = v.trim();
      // Se estiver vazio, volta a listar os produtos automaticamente.
      _search(q);
    });
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _ReceiptItemsRepo.searchProducts(q);
      if (!mounted) return;

      final list = List<Map<String, Object?>>.from(rows);
      final sel = _selectedNorm;
      if (sel != null) _pinSuggestionInPlace(list, sel);

      setState(() => _suggestions = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Falha ao buscar produtos. Tente novamente.');
      _showSnack('Erro na busca: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory(
    String normName,
    String display, {
    bool scrollToTop = true,
  }) async {
    // Fecha teclado e "foca" na seção de histórico.
    _searchFocus.unfocus();

    setState(() {
      _selectedNorm = normName;
      _selectedDisplay = display;
      _history = const [];
      _loading = true;
      _error = null;

      // Mantém o item selecionado no topo da lista de sugestões.
      final list = List<Map<String, Object?>>.from(_suggestions);
      _pinSuggestionInPlace(list, normName);
      _suggestions = list;
    });

    try {
      final rows = await _ReceiptItemsRepo.getHistoryByNormName(normName);
      if (!mounted) return;
      setState(() => _history = rows);

      if (scrollToTop) {
        await _scrollToTop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Falha ao carregar histórico. Tente novamente.');
      _showSnack('Erro ao carregar histórico: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshSelected() async {
    final norm = _selectedNorm;
    if (norm == null) return;
    await _loadHistory(norm, _selectedDisplay, scrollToTop: false);
  }

  void _clearAll() {
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _error = null;
      _selectedNorm = null;
      _selectedDisplay = '';
      _history = const [];
    });
    _scrollToTop();
    // Volta a listar produtos automaticamente.
    _search('');
  }

  int? _itemIdFromRow(Map<String, Object?> row) {
    const keys = ['id', 'item_id', 'receipt_item_id'];
    for (final k in keys) {
      final v = row[k];
      final id = (v as num?)?.toInt();
      if (id != null && id > 0) return id;
    }
    return null;
  }

  String _fmtDateMs(Object? ms) {
    final v = (ms as num?)?.toInt();
    if (v == null) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(v);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _fmtMoney(Object? n) {
    final v = (n as num?)?.toDouble() ?? 0.0;
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return 'R\$ $s';
  }

  double? _parseMoney(String input) {
    // Aceita: "12,34", "R$ 12,34", "1.234,56"
    var s = input.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll('R\$', '').trim();
    s = s.replaceAll(' ', '');
    // remove separador de milhar (.)
    s = s.replaceAll('.', '');
    // decimal (,) -> (.)
    s = s.replaceAll(',', '.');
    final v = double.tryParse(s);
    return v;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editPrice(Map<String, Object?> row) async {
    final itemId = _itemIdFromRow(row);
    if (itemId == null) {
      _showSnack(
        'Não foi possível editar: o histórico não retornou o ID do item.',
      );
      return;
    }

    final current = (row['price'] as num?)?.toDouble() ?? 0.0;
    final ctrl = TextEditingController(
      text: current.toStringAsFixed(2).replaceAll('.', ','),
    );

    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Editar preço'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedDisplay.isEmpty ? 'Produto' : _selectedDisplay,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Novo preço (R\$)',
                  hintText: 'Ex: 12,34',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final v = _parseMoney(ctrl.text);
                if (v == null || v < 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Informe um valor válido.')),
                  );
                  return;
                }
                Navigator.of(ctx).pop(v);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    setState(() => _loading = true);
    try {
      await _ReceiptItemsRepo.updateReceiptItemPrice(
        itemId: itemId,
        newPrice: result,
      );
      if (!mounted) return;
      _showSnack('Preço atualizado.');
      await _refreshSelected();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao atualizar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteItem(Map<String, Object?> row) async {
    final itemId = _itemIdFromRow(row);
    if (itemId == null) {
      _showSnack(
        'Não foi possível excluir: o histórico não retornou o ID do item.',
      );
      return;
    }

    final txId = (row['tx_id'] as num?)?.toInt() ?? 0;
    final date = _fmtDateMs(row['date_ms']);
    final price = _fmtMoney(row['price']);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Excluir item'),
            content: Text(
              'Tem certeza que deseja excluir este registro?\n\n'
              'Data: $date\n'
              'Preço: $price\n'
              'Tx: $txId',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _loading = true);
    try {
      await _ReceiptItemsRepo.deleteReceiptItem(itemId: itemId);
      if (!mounted) return;
      _showSnack('Item excluído.');
      await _refreshSelected();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao excluir: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    if (_selectedNorm != null) {
      await _refreshSelected();
      return;
    }
    await _search(_searchCtrl.text.trim());
  }

  void _clearSelection() {
    setState(() {
      _selectedNorm = null;
      _selectedDisplay = '';
      _history = const [];
      _error = null;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_scrollCtrl.hasClients) return;
    await _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _pinSuggestionInPlace(List<Map<String, Object?>> list, String normName) {
    final idx = list.indexWhere((r) => (r['norm_name'] as String?) == normName);
    if (idx <= 0) return;
    final item = list.removeAt(idx);
    list.insert(0, item);
  }

  Map<String, Object?>? _findSuggestion(String normName) {
    try {
      return _suggestions.firstWhere(
        (r) => (r['norm_name'] as String?) == normName,
      );
    } catch (_) {
      return null;
    }
  }

  String _stripDiacritics(String input) {
    const from = 'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñÝŸýÿ';
    const to = 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNnYYyy';
    var s = input;
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s;
  }

  String _normName(String raw) {
    var s = raw.trim();
    s = _stripDiacritics(s);
    s = s.toLowerCase();
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  Future<void> _openAddSheet() async {
    final nameCtrl = TextEditingController(
      text: _selectedDisplay.isNotEmpty
          ? _selectedDisplay
          : (_searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : ''),
    );
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final unitCtrl = TextEditingController(text: 'un');
    final marketCtrl = TextEditingController();

    DateTime date = DateTime.now();

    final result = await showModalBottomSheet<_ManualItemInput?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final cs = Theme.of(ctx).colorScheme;
            final isSelectedMode = _selectedNorm != null;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isSelectedMode
                              ? 'Adicionar preço'
                              : 'Adicionar produto',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome do produto',
                      prefixIcon: Icon(Icons.shopping_bag_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Preço (R\$)',
                      hintText: 'Ex: 12,90',
                      prefixIcon: Icon(Icons.payments_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: false,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Qtd',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: unitCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Unidade',
                            hintText: 'un / kg / L',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  TextField(
                    controller: marketCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mercado (opcional)',
                      prefixIcon: Icon(Icons.storefront_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) return;
                      setModal(() => date = picked);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.65),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Data: ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            'Alterar',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(ctx).pop(
                              _ManualItemInput(
                                rawName: nameCtrl.text.trim(),
                                priceText: priceCtrl.text.trim(),
                                qtyText: qtyCtrl.text.trim(),
                                unit: unitCtrl.text.trim(),
                                market: marketCtrl.text.trim(),
                                date: date,
                              ),
                            );
                          },
                          child: const Text('Salvar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    final raw = result.rawName.trim();
    if (raw.isEmpty) {
      _showSnack('Informe o nome do produto.');
      return;
    }

    final price = _parseMoney(result.priceText);
    if (price == null || price <= 0) {
      _showSnack('Informe um preço válido.');
      return;
    }

    double? qty;
    if (result.qtyText.trim().isNotEmpty) {
      final q = _parseMoney(result.qtyText.replaceAll('R\$', ''));
      if (q != null && q > 0) qty = q;
    }

    final norm = _normName(raw);
    if (norm.isEmpty) {
      _showSnack('Nome inválido. Tente novamente.');
      return;
    }

    try {
      setState(() => _loading = true);
      await _ReceiptItemsRepo.insertReceiptItem(
        rawName: raw,
        normName: norm,
        price: price,
        dateMs: result.date.millisecondsSinceEpoch,
        qty: qty,
        unit: result.unit,
        market: result.market,
      );
      if (!mounted) return;

      _showSnack('Registro adicionado.');

      // Atualiza lista e já abre o histórico do item.
      await _search(_searchCtrl.text.trim());
      await _loadHistory(norm, raw);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao adicionar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final selNorm = _selectedNorm;
    final selSug = selNorm == null ? null : _findSuggestion(selNorm);

    final selCount = (selSug?['count'] as num?)?.toInt() ?? _history.length;
    final selLastPrice = selSug == null ? '' : _fmtMoney(selSug['last_price']);
    final selLastDate = selSug == null ? '' : _fmtDateMs(selSug['last_date']);

    final hasSuggestions = _suggestions.isNotEmpty;

    final historySliver = selNorm == null
        ? SliverToBoxAdapter(
            child: _EmptyHint(color: cs.onSurface.withOpacity(0.7)),
          )
        : _history.isEmpty
        ? SliverToBoxAdapter(
            child: _loading
                ? const SizedBox.shrink()
                : _EmptyHistoryHint(color: cs.onSurface.withOpacity(0.7)),
          )
        : SliverList.separated(
            itemCount: _history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final row = _history[i];
              final date = _fmtDateMs(row['date_ms']);
              final price = _fmtMoney(row['price']);
              final market = (row['market'] as String?)?.trim();
              final txId = (row['tx_id'] as num?)?.toInt();
              final qty = (row['qty'] as num?)?.toDouble();
              final unit = (row['unit'] as String?)?.trim();

              String fmtQty(double v) =>
                  (v % 1 == 0) ? v.toInt().toString() : v.toString();

              final subtitle = [
                if (qty != null && qty > 0 && unit != null && unit.isNotEmpty)
                  '${fmtQty(qty)} $unit',
                if (market != null && market.isNotEmpty) market,
                if (txId != null && txId > 0) 'Tx: $txId',
              ].join(' • ');

              final canEdit = _itemIdFromRow(row) != null;

              return _HistoryTile(
                date: date,
                subtitle: subtitle.isEmpty ? '—' : subtitle,
                price: price,
                canEdit: canEdit,
                onEdit: () => _editPrice(row),
                onDelete: () => _deleteItem(row),
              );
            },
          );

    final suggestionsSliver = hasSuggestions
        ? SliverList.separated(
            itemCount: _suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final r = _suggestions[i];
              final norm = (r['norm_name'] as String?) ?? '';
              final display = (r['display_name'] as String?) ?? norm;
              final count = (r['count'] as num?)?.toInt() ?? 0;

              final lastPrice = _fmtMoney(r['last_price']);
              final lastDate = _fmtDateMs(r['last_date']);

              if (norm.isEmpty) return const SizedBox.shrink();

              final selected = norm == _selectedNorm;

              return _SuggestionTile(
                title: display,
                count: count,
                lastPrice: lastPrice,
                lastDate: lastDate,
                selected: selected,
                onTap: () => _loadHistory(norm, display),
              );
            },
          )
        : const SliverToBoxAdapter(child: SizedBox.shrink());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preços de Produtos'),
        actions: [
          IconButton(
            tooltip: 'Adicionar',
            onPressed: _openAddSheet,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Limpar',
            onPressed: _clearAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add),
        label: Text(selNorm == null ? 'Adicionar produto' : 'Adicionar preço'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: CustomScrollView(
            controller: _scrollCtrl,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                sliver: SliverToBoxAdapter(
                  child: _SearchCard(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    onChanged: _onSearchChanged,
                    onClear: _clearAll,
                    loading: _loading,
                    error: _error,
                  ),
                ),
              ),

              if (selNorm != null) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: _SelectedProductCard(
                      title: _selectedDisplay,
                      count: selCount,
                      lastPrice: selLastPrice,
                      lastDate: selLastDate,
                      onAdd: _openAddSheet,
                      onClear: _clearSelection,
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Histórico',
                      subtitle: _history.isEmpty && !_loading
                          ? 'Sem registros ainda. Adicione um preço!'
                          : 'Deslize para baixo para atualizar',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  sliver: historySliver,
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Trocar produto',
                      subtitle: hasSuggestions
                          ? 'Toque em um item para abrir o histórico'
                          : null,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  sliver: suggestionsSliver,
                ),
              ] else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: hasSuggestions
                          ? const _SectionHeader(
                              title: 'Sugestões',
                              subtitle:
                                  'Produtos recentes (use a busca para filtrar)',
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  sliver: suggestionsSliver,
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  sliver: historySliver,
                ),
              ],

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 80),
                  child: Text(
                    'Dica: os nomes são normalizados (sem acento) para facilitar a busca.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.55),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool loading;
  final String? error;

  const _SearchCard({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Pesquisar produto (ex: banana, arroz, leite)',
                border: const OutlineInputBorder(),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar',
                        icon: const Icon(Icons.close),
                        onPressed: onClear,
                      ),
              ),
            ),
            if (loading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                minHeight: 4,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(0.65),
            ),
          ),
        ],
      ],
    );
  }
}

class _SelectedProductCard extends StatelessWidget {
  final String title;
  final int count;
  final String lastPrice;
  final String lastDate;
  final VoidCallback onAdd;
  final VoidCallback onClear;

  const _SelectedProductCard({
    required this.title,
    required this.count,
    required this.lastPrice,
    required this.lastDate,
    required this.onAdd,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: cs.primary.withOpacity(0.10),
                  ),
                  child: Icon(Icons.star_rounded, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Produto selecionado' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$count registro(s) • Último: $lastPrice ${lastDate.isEmpty ? '' : '($lastDate)'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.60),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar preço'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear),
                  label: const Text('Limpar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String title;
  final int count;
  final String lastPrice;
  final String lastDate;
  final bool selected;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.title,
    required this.count,
    required this.lastPrice,
    required this.lastDate,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: selected ? cs.primary.withOpacity(0.10) : cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: selected
                      ? cs.primary.withOpacity(0.16)
                      : cs.surfaceContainerHighest.withOpacity(0.55),
                ),
                alignment: Alignment.center,
                child: Text(
                  title.isNotEmpty ? title[0].toUpperCase() : 'P',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Último: $lastPrice ${lastDate.isEmpty ? '' : '• $lastDate'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.60),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: cs.secondaryContainer.withOpacity(0.65),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.chevron_right,
                color: selected ? cs.primary : cs.onSurface.withOpacity(0.60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualItemInput {
  final String rawName;
  final String priceText;
  final String qtyText;
  final String unit;
  final String market;
  final DateTime date;

  const _ManualItemInput({
    required this.rawName,
    required this.priceText,
    required this.qtyText,
    required this.unit,
    required this.market,
    required this.date,
  });
}

class _HistoryTile extends StatelessWidget {
  final String date;
  final String subtitle;
  final String price;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.date,
    required this.subtitle,
    required this.price,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canEdit ? onEdit : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.78),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(price, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Ações',
                enabled: canEdit,
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.edit),
                      title: Text('Editar preço'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete, color: cs.error),
                      title: Text('Excluir', style: TextStyle(color: cs.error)),
                    ),
                  ),
                ],
                child: Icon(
                  Icons.more_vert,
                  color: canEdit
                      ? cs.onSurface.withOpacity(0.70)
                      : cs.onSurface.withOpacity(0.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final Color color;
  const _EmptyHint({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Text(
        'Selecione um produto para ver o histórico. Você também pode pesquisar ou adicionar manualmente.',
        style: TextStyle(color: color),
      ),
    );
  }
}

class _EmptyHistoryHint extends StatelessWidget {
  final Color color;
  const _EmptyHistoryHint({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Text(
        'Sem histórico para este produto. Toque em "Adicionar preço" para registrar o primeiro.',
        style: TextStyle(color: color),
      ),
    );
  }
}
