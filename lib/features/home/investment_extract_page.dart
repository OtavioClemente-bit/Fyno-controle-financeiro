import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models/tx_item.dart';
import 'repositories/tx_repository.dart';

import '../../shared/format/format_br.dart';

/// Extrato dedicado para investimentos.
///
/// Regras desta tela:
/// - Considera como "investimento" qualquer lançamento que contenha termos como
///   "investimento", "rendimento", "selic", "tesouro", "ações", "fii", etc.
/// - **Não existe "saída" para investimentos**: aqui mostramos apenas lançamentos
///   marcados como `isIncome == true`.
/// - O usuário pode **excluir** um lançamento de investimento (apaga do banco),
///   removendo também do extrato geral.
class InvestmentExtractPage extends StatefulWidget {
  const InvestmentExtractPage({super.key});

  @override
  State<InvestmentExtractPage> createState() => _InvestmentExtractPageState();
}

enum _InvPeriod { month, last30, custom }

class _InvestmentExtractPageState extends State<InvestmentExtractPage> {
  final TxRepository _repo = TxRepository();

  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;

  List<TxItem> _all = [];
  List<TxItem> _base = [];
  List<TxItem> _list = [];

  // Period
  _InvPeriod _period = _InvPeriod.month;
  DateTime _refMonth = DateTime.now();
  DateTime? _customStart;
  DateTime? _customEnd;

  // Filters
  String? _kind; // can be a real kind (e.g. "Selic") or the group "Ações"
  String _query = '';

  // Summary
  double _totalApplied = 0;
  Map<String, double> _byKind = {};
  Map<String, double> _byKindForChart = {};
  List<String> _kinds = [];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text;
      if (q == _query) return;
      setState(() => _query = q);
      _recalc();
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _repo.getAll();
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
    });
    _recalc();
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);

  DateTime _monthEndExclusive(DateTime d) {
    final nextMonth = DateTime(d.year, d.month + 1, 1);
    return DateTime(nextMonth.year, nextMonth.month, 1);
  }

  DateTimeRange _periodRange() {
    if (_period == _InvPeriod.month) {
      return DateTimeRange(
        start: _monthStart(_refMonth),
        end: _monthEndExclusive(_refMonth),
      );
    }
    if (_period == _InvPeriod.last30) {
      final end = DateTime.now();
      final start = end.subtract(const Duration(days: 30));
      return DateTimeRange(
        start: DateTime(start.year, start.month, start.day),
        end: end,
      );
    }

    final now = DateTime.now();
    final start = _customStart ?? DateTime(now.year, now.month, now.day);
    final end = _customEnd ?? now;

    // end exclusive (+1 day) to include selected end date
    final endExclusive = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));
    return DateTimeRange(
      start: DateTime(start.year, start.month, start.day),
      end: endExclusive,
    );
  }

  String _money(double v) => FormatBR.money(v);
  String _dayLabel(DateTime d) => FormatBR.date(d);

  // ---------------------------------------------------------------------------
  // Investment detection + kind extraction
  // ---------------------------------------------------------------------------

  String _rmAccents(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    var out = s;
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }

  String _norm(String s) => _rmAccents(s).toLowerCase().trim();

  bool _looksLikeInvestment(TxItem tx) {
    final hay = _norm('${tx.title} ${tx.note ?? ''} ${tx.category}');
    // Keep it permissive, because legacy data may use "Rendimentos" etc.
    const keys = <String>[
      'invest',
      'investimento',
      'rend',
      'rendimento',
      'selic',
      'tesouro',
      'acao',
      'ações',
      'fii',
      'fiis',
      'cripto',
      'bitcoin',
      'ethereum',
      'poupanca',
      'poupança',
    ];
    for (final k in keys) {
      if (hay.contains(_norm(k))) return true;
    }
    return false;
  }

  /// Extracts the "tipo de investimento" chosen in AddTransactionPage.
  /// It is stored as a line like: "`Investimento: <tipo>`" inside tx.note,
  /// and may also appear in the title: "`Investimento — <tipo>`".
  String _investmentKindOf(TxItem tx) {
    final note = (tx.note ?? '').trim();
    if (note.isNotEmpty) {
      final re = RegExp(
        r'^\s*Investimento\s*:\s*(.+?)\s*$',
        multiLine: true,
        caseSensitive: false,
      );
      final m = re.firstMatch(note);
      if (m != null) return m.group(1)!.trim();
    }

    final title = tx.title.trim();
    final reTitle = RegExp(
      r'^\s*Investimento\s*[-—–]\s*(.+?)\s*$',
      caseSensitive: false,
    );
    final m2 = reTitle.firstMatch(title);
    if (m2 != null) return m2.group(1)!.trim();

    // fallback: use category (still helps filter visually)
    final cat = tx.category.trim();
    return cat.isEmpty ? 'Investimento' : cat;
  }

  // ---------------------------------------------------------------------------
  // "Ações" grouping (only for chart)
  // ---------------------------------------------------------------------------

  bool _looksLikeStockTicker(String kind) {
    final k = kind.trim().toUpperCase();
    // Common BR tickers: PETR4, ITSA4, WEGE3, BBAS3...
    // Avoid grouping FIIs by default (often end with 11).
    final re = RegExp(r'^[A-Z]{4}\d{1,2}$');
    if (!re.hasMatch(k)) return false;
    if (k.endsWith('11')) return false;
    return true;
  }

  bool _isActionsKind(String kind) {
    final n = _norm(kind);
    if (n.contains('acao') || n.contains('ações') || n.contains('acoes')) {
      return true;
    }
    return _looksLikeStockTicker(kind);
  }

  String _chartBucketLabel(String kind) =>
      _isActionsKind(kind) ? 'Ações' : kind;

  bool _matchesSelectedKind(String kind) {
    if (_kind == null) return true;
    if (_norm(_kind!) == _norm('Ações')) return _isActionsKind(kind);
    return _norm(kind) == _norm(_kind!);
  }

  double _selectedTotal() {
    if (_kind == null) return _totalApplied;

    if (_norm(_kind!) == _norm('Ações')) {
      double sum = 0;
      _byKind.forEach((k, v) {
        if (_isActionsKind(k)) sum += v;
      });
      return sum;
    }

    final key = _byKind.keys.cast<String?>().firstWhere(
      (k) => k != null && _norm(k) == _norm(_kind!),
      orElse: () => _kind,
    );
    return _byKind[key] ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Recalc
  // ---------------------------------------------------------------------------

  void _recalc() {
    final range = _periodRange();
    final start = range.start;
    final end = range.end;

    // Only investments, only incomes (no "saída" in investimentos).
    final invAll = _all.where(_looksLikeInvestment).toList();

    final base = <TxItem>[];
    for (final tx in invAll) {
      if (!tx.isIncome) continue;

      final d = tx.date;
      if (d.isBefore(start) || !d.isBefore(end)) continue;
      base.add(tx);
    }

    // Breakdown by kind (period-only)
    final kindsSet = <String>{};
    final byKind = <String, double>{};
    double total = 0;

    for (final tx in base) {
      final kind = _investmentKindOf(tx);
      kindsSet.add(kind);

      final v = tx.amount;
      total += v;
      byKind[kind] = (byKind[kind] ?? 0) + v;
    }

    final sortedKinds = kindsSet.toList()
      ..sort((a, b) => _norm(a).compareTo(_norm(b)));

    // Decide whether we should add the group "Ações" in kind dropdown.
    final hasActions = sortedKinds.any(_isActionsKind);
    final hasMoreThanOneActionKind =
        sortedKinds.where(_isActionsKind).toSet().length >= 2;
    final hasAnyTickerLike = sortedKinds.any(_looksLikeStockTicker);

    final shouldAddActionsGroup =
        hasActions &&
        (!sortedKinds.any((k) => _norm(k) == _norm('Ações'))) &&
        (hasMoreThanOneActionKind || hasAnyTickerLike);

    final kindsForUi = <String>[
      if (shouldAddActionsGroup) 'Ações',
      ...sortedKinds,
    ];

    // Chart map (same values, but grouped for chart only)
    final chartMap = <String, double>{};
    byKind.forEach((k, v) {
      final bucket = _chartBucketLabel(k);
      chartMap[bucket] = (chartMap[bucket] ?? 0) + v;
    });

    // Apply kind + query filters to list
    final q = _norm(_query);
    final filtered = <TxItem>[];
    for (final tx in base) {
      final kind = _investmentKindOf(tx);

      if (!_matchesSelectedKind(kind)) continue;

      if (q.isNotEmpty) {
        final hay = _norm('${tx.title} ${tx.note ?? ''} ${tx.category} $kind');
        if (!hay.contains(q)) continue;
      }
      filtered.add(tx);
    }

    // Sort newest first
    filtered.sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      _base = base;
      _list = filtered;

      _kinds = kindsForUi;
      _byKind = byKind;
      _byKindForChart = chartMap;
      _totalApplied = total;

      // If current filter became invalid (e.g. removed), clear it.
      if (_kind != null) {
        final valid =
            _norm(_kind!) == _norm('Ações') ||
            sortedKinds.any((k) => _norm(k) == _norm(_kind!));
        if (!valid) _kind = null;
      }
    });
  }

  String _periodLabel(
    _InvPeriod p,
    DateTime refMonth,
    DateTime? a,
    DateTime? b,
  ) {
    String mm(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.year}';

    switch (p) {
      case _InvPeriod.month:
        return 'Mês: ${mm(refMonth)}';
      case _InvPeriod.last30:
        return 'Últimos 30 dias';
      case _InvPeriod.custom:
        final sa = a == null ? '—' : FormatBR.date(a);
        final sb = b == null ? '—' : FormatBR.date(b);
        return 'Período: $sa → $sb';
    }
  }

  IconData _iconForKind(String kind) {
    final n = _norm(kind);

    if (_isActionsKind(kind)) return Icons.show_chart_rounded;
    if (n.contains('tesouro') || n.contains('selic')) {
      return Icons.account_balance_rounded;
    }
    if (n.contains('fii')) return Icons.apartment_rounded;
    if (n.contains('cripto') ||
        n.contains('bitcoin') ||
        n.contains('ethereum')) {
      return Icons.currency_bitcoin_rounded;
    }
    if (n.contains('poupanc')) return Icons.savings_rounded;
    if (n.contains('rend')) return Icons.trending_up_rounded;

    return Icons.pie_chart_rounded;
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  bool _sameTx(TxItem a, TxItem b) {
    return a.title == b.title &&
        a.amount == b.amount &&
        a.category == b.category &&
        a.isIncome == b.isIncome &&
        a.date == b.date &&
        (a.note ?? '') == (b.note ?? '');
  }

  Future<void> _deleteFromRepo(TxItem tx) async {
    final dynamic repo = _repo;
    final dynamic dtx = tx;

    dynamic id;
    try {
      id = dtx.id;
    } catch (_) {}
    try {
      id ??= dtx.txId;
    } catch (_) {}
    try {
      id ??= dtx.uuid;
    } catch (_) {}

    // Try common repository APIs (id-first, then object).
    final attempts = <Future<void> Function()>[
      if (id != null) () async => await repo.delete(id),
      if (id != null) () async => await repo.deleteById(id),
      if (id != null) () async => await repo.deleteTx(id),
      if (id != null) () async => await repo.remove(id),
      () async => await repo.delete(tx),
      () async => await repo.deleteTx(tx),
      () async => await repo.remove(tx),
      () async => await repo.deleteItem(tx),
      if (id != null) () async => await repo.deleteTransaction(id),
      () async => await repo.deleteTransaction(tx),
    ];

    Object? lastErr;
    for (final fn in attempts) {
      try {
        await fn();
        return;
      } catch (e) {
        lastErr = e;
      }
    }

    throw lastErr ?? Exception('Não foi possível excluir o lançamento.');
  }

  Future<void> _confirmAndDelete(TxItem tx) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: const Text('Excluir investimento?'),
              content: Text(
                'Isso vai apagar o lançamento do banco de dados e ele também vai sumir do extrato geral.\n\n'
                '• ${tx.title}\n'
                '• ${_money(tx.amount)} em ${_dayLabel(tx.date)}',
                style: TextStyle(color: cs.onSurface),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Excluir'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok) return;

    try {
      await _deleteFromRepo(tx);
      if (!mounted) return;

      setState(() {
        _all.removeWhere((t) => _sameTx(t, tx));
      });
      _recalc();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Investimento excluído.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não consegui excluir do banco. Confira o TxRepository.',
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final periodLabel = _periodLabel(
      _period,
      _refMonth,
      _customStart,
      _customEnd,
    );
    final selectedTotal = _selectedTotal();
    final titleLabel = _kind == null ? 'Saldo investido' : 'Saldo em ${_kind!}';

    final selectedChartKey = _kind == null ? null : _chartBucketLabel(_kind!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Investimentos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  _FiltersCard(
                    period: _period,
                    refMonth: _refMonth,
                    customStart: _customStart,
                    customEnd: _customEnd,
                    kinds: _kinds,
                    selectedKind: _kind,
                    searchController: _searchCtrl,
                    onPeriodChanged: (p) {
                      setState(() => _period = p);
                      _recalc();
                    },
                    onMonthChanged: (m) {
                      setState(() => _refMonth = m);
                      _recalc();
                    },
                    onCustomChanged: (a, b) {
                      setState(() {
                        _customStart = a;
                        _customEnd = b;
                      });
                      _recalc();
                    },
                    onKindChanged: (k) {
                      setState(
                        () => _kind = (k == null || k.isEmpty) ? null : k,
                      );
                      _recalc();
                    },
                    onClear: () {
                      setState(() {
                        _kind = null;
                        _query = '';
                        _searchCtrl.text = '';
                      });
                      _recalc();
                    },
                  ),

                  const SizedBox(height: 12),

                  _SummaryCard(
                    title: titleLabel,
                    value: selectedTotal,
                    periodLabel: periodLabel,
                    count: _list.length,
                    hasFilter: _kind != null || _query.trim().isNotEmpty,
                    money: _money,
                  ),

                  const SizedBox(height: 12),

                  _AllocationCard(
                    byKind: _byKindForChart,
                    selectedKey: selectedChartKey,
                    money: _money,
                    iconFor: _iconForKind,
                    onTapKey: (k) {
                      setState(() => _kind = k);
                      _recalc();
                    },
                  ),

                  const SizedBox(height: 12),

                  _ListHeader(count: _list.length, periodLabel: periodLabel),

                  const SizedBox(height: 8),

                  if (_base.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: _EmptyState(
                        title: 'Nada por aqui ainda',
                        subtitle:
                            'Nenhum lançamento de investimento (entrada) encontrado no período.',
                        icon: Icons.savings_outlined,
                      ),
                    )
                  else if (_list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: _EmptyState(
                        title: 'Sem resultados',
                        subtitle: 'Ajuste os filtros ou limpe a busca.',
                        icon: Icons.search_off_rounded,
                      ),
                    )
                  else
                    ..._list.map((tx) {
                      final kind = _investmentKindOf(tx);
                      return _TxCard(
                        tx: tx,
                        kind: kind,
                        money: _money,
                        dayLabel: _dayLabel,
                        icon: _iconForKind(kind),
                        onDelete: () => _confirmAndDelete(tx),
                      );
                    }),

                  const SizedBox(height: 24),

                  if (_base.isNotEmpty)
                    Text(
                      'Dica: investimentos aqui são sempre “entrada”. '
                      'Se algo não faz mais sentido, exclua o lançamento.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Widgets
// -----------------------------------------------------------------------------

class _FiltersCard extends StatelessWidget {
  final _InvPeriod period;
  final DateTime refMonth;
  final DateTime? customStart;
  final DateTime? customEnd;

  final List<String> kinds;
  final String? selectedKind;

  final TextEditingController searchController;

  final ValueChanged<_InvPeriod> onPeriodChanged;
  final ValueChanged<DateTime> onMonthChanged;
  final void Function(DateTime? start, DateTime? end) onCustomChanged;

  final ValueChanged<String?> onKindChanged;
  final VoidCallback onClear;

  const _FiltersCard({
    required this.period,
    required this.refMonth,
    required this.customStart,
    required this.customEnd,
    required this.kinds,
    required this.selectedKind,
    required this.searchController,
    required this.onPeriodChanged,
    required this.onMonthChanged,
    required this.onCustomChanged,
    required this.onKindChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final InputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outlineVariant),
    );

    final fill = cs.surfaceContainerHighest;

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<_InvPeriod>(
                    initialValue: period,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Período',
                      filled: true,
                      fillColor: fill,
                      border: border,
                      enabledBorder: border,
                      focusedBorder: border,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _InvPeriod.month,
                        child: Text('Mês'),
                      ),
                      DropdownMenuItem(
                        value: _InvPeriod.last30,
                        child: Text('Últimos 30 dias'),
                      ),
                      DropdownMenuItem(
                        value: _InvPeriod.custom,
                        child: Text('Personalizado'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      onPeriodChanged(v);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Limpar filtros',
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (period == _InvPeriod.month)
              _MonthPickerRow(refMonth: refMonth, onChanged: onMonthChanged),
            if (period == _InvPeriod.custom)
              _CustomPeriodRow(
                start: customStart,
                end: customEnd,
                onChanged: onCustomChanged,
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: selectedKind,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Tipo',
                filled: true,
                fillColor: fill,
                border: border,
                enabledBorder: border,
                focusedBorder: border,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos'),
                ),
                ...kinds.map(
                  (k) => DropdownMenuItem<String?>(value: k, child: Text(k)),
                ),
              ],
              onChanged: (v) => onKindChanged(v),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: 'Buscar',
                hintText: 'Ex: Selic, Tesouro, Ações, ITSA4...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: fill,
                border: border,
                enabledBorder: border,
                focusedBorder: border,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              textInputAction: TextInputAction.search,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPickerRow extends StatelessWidget {
  final DateTime refMonth;
  final ValueChanged<DateTime> onChanged;

  const _MonthPickerRow({required this.refMonth, required this.onChanged});

  String _label() {
    final m = refMonth.month.toString().padLeft(2, '0');
    return '$m/${refMonth.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.onSurface,
              side: BorderSide(color: cs.outlineVariant),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () =>
                onChanged(DateTime(refMonth.year, refMonth.month - 1, 1)),
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Anterior'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              _label(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.onSurface,
              side: BorderSide(color: cs.outlineVariant),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () =>
                onChanged(DateTime(refMonth.year, refMonth.month + 1, 1)),
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Próximo'),
          ),
        ),
      ],
    );
  }
}

class _CustomPeriodRow extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime? start, DateTime? end) onChanged;

  const _CustomPeriodRow({
    required this.start,
    required this.end,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Future<void> pick(bool isStart) async {
      final now = DateTime.now();
      final initial = (isStart ? start : end) ?? now;

      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(now.year - 10),
        lastDate: DateTime(now.year + 10),
      );
      if (picked == null) return;

      if (isStart) {
        onChanged(picked, end);
      } else {
        onChanged(start, picked);
      }
    }

    String s = start == null ? 'Início' : FormatBR.date(start!);
    String e = end == null ? 'Fim' : FormatBR.date(end!);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => pick(true),
            icon: const Icon(Icons.event_rounded),
            label: Text(s),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => pick(false),
            icon: const Icon(Icons.event_available_rounded),
            label: Text(e),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final String periodLabel;
  final int count;
  final bool hasFilter;
  final String Function(double) money;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.periodLabel,
    required this.count,
    required this.hasFilter,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (hasFilter)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(
                      'Filtro ativo',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              money(value),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniChip(
                  icon: Icons.calendar_month_rounded,
                  label: periodLabel,
                ),
                _MiniChip(
                  icon: Icons.receipt_long_rounded,
                  label: '$count lançamentos',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationCard extends StatelessWidget {
  final Map<String, double> byKind;
  final String? selectedKey;

  final String Function(double) money;
  final IconData Function(String) iconFor;
  final ValueChanged<String> onTapKey;

  const _AllocationCard({
    required this.byKind,
    required this.selectedKey,
    required this.money,
    required this.iconFor,
    required this.onTapKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (byKind.isEmpty) {
      return Card(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Alocação indisponível (sem saldo no período).',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final entries = byKind.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = entries.fold<double>(0, (p, e) => p + e.value);

    final colors = _ChartColors.palette(cs, entries.length);
    final colorsByKey = <String, Color>{};
    for (var i = 0; i < entries.length; i++) {
      colorsByKey[entries[i].key] = colors[i];
    }

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alocação',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  height: 132,
                  child: _DonutChart(
                    entries: entries,
                    total: total,
                    selectedKey: selectedKey,
                    colorsByKey: colorsByKey,
                    centerLabel: 'Total',
                    centerValue: money(total),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      for (final e in entries.take(6))
                        _AllocRow(
                          label: e.key,
                          value: e.value,
                          total: total,
                          money: money,
                          icon: iconFor(e.key),
                          color: colorsByKey[e.key]!,
                          selected:
                              selectedKey != null &&
                              _norm(selectedKey!) == _norm(e.key),
                          onTap: () => onTapKey(e.key),
                        ),
                      if (entries.length > 6)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '+${entries.length - 6} tipos...',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _rmAccents(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    var out = s;
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }

  String _norm(String s) => _rmAccents(s).toLowerCase().trim();
}

class _AllocRow extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final String Function(double) money;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AllocRow({
    required this.label,
    required this.value,
    required this.total,
    required this.money,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = total <= 0 ? 0.0 : (value / total);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartColors {
  static List<Color> palette(ColorScheme cs, int n) {
    // High-contrast, deterministic palette generated from the primary hue.
    final base = HSLColor.fromColor(cs.primary);
    final sat = math.max(0.58, base.saturation);
    final light = cs.brightness == Brightness.dark ? 0.55 : 0.45;

    final out = <Color>[];
    for (var i = 0; i < n; i++) {
      final hue = (base.hue + (360.0 / math.max(1, n)) * i) % 360.0;
      out.add(HSLColor.fromAHSL(1.0, hue, sat, light).toColor());
    }
    return out;
  }
}

class _DonutChart extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final double total;
  final String? selectedKey;

  final Map<String, Color> colorsByKey;

  final String centerLabel;
  final String centerValue;

  const _DonutChart({
    required this.entries,
    required this.total,
    required this.selectedKey,
    required this.colorsByKey,
    required this.centerLabel,
    required this.centerValue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _DonutPainter(
              entries: entries,
              total: total,
              selectedKey: selectedKey,
              colorScheme: cs,
              colorsByKey: colorsByKey,
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                centerValue,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final double total;
  final String? selectedKey;
  final ColorScheme colorScheme;
  final Map<String, Color> colorsByKey;

  _DonutPainter({
    required this.entries,
    required this.total,
    required this.selectedKey,
    required this.colorScheme,
    required this.colorsByKey,
  });

  String _rmAccents(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    var out = s;
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }

  String _norm(String s) => _rmAccents(s).toLowerCase().trim();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final stroke = radius * 0.26;
    final ringRadius = radius - stroke / 2;

    // Background ring
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = colorScheme.outlineVariant.withOpacity(0.55);
    canvas.drawCircle(center, ringRadius, bg);

    if (total <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: ringRadius);

    var startAngle = -math.pi / 2;
    const gap = 0.035; // radians gap between segments

    for (final e in entries) {
      final v = e.value;
      if (v <= 0) continue;

      final pct = v / total;
      final sweep = pct * 2 * math.pi;
      final drawSweep = math.max(0.0, sweep - gap).toDouble();

      final isSel = selectedKey != null && _norm(selectedKey!) == _norm(e.key);

      final c = colorsByKey[e.key] ?? colorScheme.primary;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? (stroke + 2) : stroke
        ..strokeCap = StrokeCap.round
        ..color = c;

      canvas.drawArc(rect, startAngle, drawSweep, false, paint);

      startAngle += sweep;
    }

    // center hole
    final holePaint = Paint()..color = colorScheme.surface;
    canvas.drawCircle(center, ringRadius - stroke / 2, holePaint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.entries != entries ||
        oldDelegate.total != total ||
        oldDelegate.selectedKey != selectedKey ||
        oldDelegate.colorsByKey != colorsByKey ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _ListHeader extends StatelessWidget {
  final int count;
  final String periodLabel;

  const _ListHeader({required this.count, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          'Lançamentos ($count)',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const Spacer(),
        Text(
          periodLabel,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _TxCard extends StatelessWidget {
  final TxItem tx;
  final String kind;

  final String Function(double) money;
  final String Function(DateTime) dayLabel;
  final IconData icon;

  final VoidCallback onDelete;

  const _TxCard({
    required this.tx,
    required this.kind,
    required this.money,
    required this.dayLabel,
    required this.icon,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final note = (tx.note ?? '').trim();
    final noteOneLine = note.isEmpty ? null : note.split('\n').first;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: cs.surfaceContainerHighest,
          child: Icon(icon, color: cs.primary),
        ),
        title: Text(
          tx.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Tag(icon: Icons.label_rounded, label: kind),
                  _Tag(icon: Icons.event_rounded, label: dayLabel(tx.date)),
                ],
              ),
              if (noteOneLine != null) ...[
                const SizedBox(height: 6),
                Text(
                  noteOneLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              money(tx.amount),
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary),
            ),
            const SizedBox(height: 6),
            InkResponse(
              onTap: onDelete,
              radius: 18,
              child: Icon(Icons.delete_outline_rounded, color: cs.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Tag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(icon, size: 52, color: cs.onSurfaceVariant),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
