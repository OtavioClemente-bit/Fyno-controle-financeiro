import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'add_transaction_page.dart';
import 'edit_transaction_page.dart';
import 'investment_extract_page.dart';
import 'models/tx_item.dart';
import 'models/tx_type.dart';
import 'repositories/tx_repository.dart';

import '../../shared/format/format_br.dart';

enum PeriodFilter { month, last7, custom }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TxRepository _repo = TxRepository();

  // --- UI state
  bool _loading = true;
  List<TxItem> _all = [];

  // filtros
  final TextEditingController _searchCtrl = TextEditingController();
  PeriodFilter _period = PeriodFilter.month;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  DateTime? _customStart;
  DateTime? _customEnd; // inclusive (vamos tratar)
  TxType? _type; // null = todos
  String? _category; // null = todas

  // resumo (baseado no que está aparecendo)
  double _saldo = 0;
  double _income = 0;
  double _expense = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _monthEndExclusive(DateTime d) => DateTime(d.year, d.month + 1, 1);

  (DateTime start, DateTime endExclusive) _periodRange() {
    final now = DateTime.now();
    switch (_period) {
      case PeriodFilter.month:
        return (_monthStart(_month), _monthEndExclusive(_month));
      case PeriodFilter.last7:
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        final end = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1));
        return (start, end);
      case PeriodFilter.custom:
        final s = _customStart ?? _monthStart(now);
        final e = _customEnd ?? now;
        final start = DateTime(s.year, s.month, s.day);
        final end = DateTime(
          e.year,
          e.month,
          e.day,
        ).add(const Duration(days: 1));
        return (start, end);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.getAll();
    if (!mounted) return;

    setState(() {
      _all = list;
      _loading = false;
    });

    _recalcSummary();
  }

  Future<void> _reload() async => _load();

  void _recalcSummary() {
    final filtered = _applyFilters(_all);
    double saldo = 0;
    double inc = 0;
    double exp = 0;

    for (final tx in filtered) {
      if (tx.isIncome) {
        inc += tx.amount;
        saldo += tx.amount;
      } else {
        exp += tx.amount;
        saldo -= tx.amount;
      }
    }

    setState(() {
      _saldo = saldo;
      _income = inc;
      _expense = exp;
    });
  }

  List<String> _availableCategories() {
    final set = <String>{};
    for (final tx in _all) {
      final c = tx.category.trim();
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  // ---- Chart (Home) — distribuição por categoria (respeita filtros, ignora seleção de categoria)
  List<TxItem> _applyFiltersForChart(List<TxItem> input) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final (start, endEx) = _periodRange();

    return input.where((tx) {
      // período
      if (tx.date.isBefore(start) || !tx.date.isBefore(endEx)) return false;

      // tipo
      if (_type != null) {
        final isIncome = tx.isIncome;
        if (_type == TxType.income && !isIncome) return false;
        if (_type == TxType.expense && isIncome) return false;
      }

      // busca
      if (q.isNotEmpty) {
        final hay = '${tx.title} ${tx.note ?? ''} ${tx.category}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }

      return true;
    }).toList()..sort((a, b) {
      final c = b.date.millisecondsSinceEpoch.compareTo(
        a.date.millisecondsSinceEpoch,
      );
      if (c != 0) return c;
      return (b.id ?? 0).compareTo(a.id ?? 0);
    });
  }

  Map<String, double> _byCategoryForChart(List<TxItem> visible) {
    final map = <String, double>{};
    for (final tx in visible) {
      var c = tx.category.trim();
      if (c.isEmpty) c = 'Sem categoria';
      // O gráfico sempre trabalha com valores positivos (distribuição).
      final v = tx.amount.abs();
      map[c] = (map[c] ?? 0) + v;
    }
    return map;
  }

  void _toggleCategoryFromChart(String key) {
    setState(() {
      final current = (_category ?? '').trim().toLowerCase();
      final next = key.trim().toLowerCase();
      _category = (current == next) ? null : key;
    });
    _recalcSummary();
  }

  List<TxItem> _applyFilters(List<TxItem> input) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final (start, endEx) = _periodRange();

    return input.where((tx) {
      // período
      final d = tx.date;
      if (d.isBefore(start) || !d.isBefore(endEx)) return false;

      // tipo
      if (_type != null) {
        final isIncome = tx.isIncome;
        if (_type == TxType.income && !isIncome) return false;
        if (_type == TxType.expense && isIncome) return false;
      }

      // categoria
      if (_category != null && _category!.trim().isNotEmpty) {
        if (tx.category.trim().toLowerCase() !=
            _category!.trim().toLowerCase()) {
          return false;
        }
      }

      // busca
      if (q.isNotEmpty) {
        final hay = '${tx.title} ${tx.note ?? ''} ${tx.category}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }

      return true;
    }).toList()..sort((a, b) {
      final c = b.date.millisecondsSinceEpoch.compareTo(
        a.date.millisecondsSinceEpoch,
      );
      if (c != 0) return c;
      return (b.id ?? 0).compareTo(a.id ?? 0);
    });
  }

  String _periodLabel() {
    switch (_period) {
      case PeriodFilter.month:
        return FormatBR.monthYear(_month);
      case PeriodFilter.last7:
        return 'Últimos 7 dias';
      case PeriodFilter.custom:
        final s = _customStart;
        final e = _customEnd;
        if (s == null || e == null) return 'Personalizado';
        return '${FormatBR.date(s)} • ${FormatBR.date(e)}';
    }
  }

  String _typeLabel() {
    if (_type == null) return 'Todos';
    return _type == TxType.income ? 'Receitas' : 'Despesas';
  }

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _type = null;
      _category = null;
      _period = PeriodFilter.month;
      _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
      _customStart = null;
      _customEnd = null;
    });
    _recalcSummary();
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta, 1);
    setState(() {
      _period = PeriodFilter.month;
      _customStart = null;
      _customEnd = null;
      _month = next;
    });
    _recalcSummary();
  }

  Future<void> _pickMonthFromTop(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      helpText: 'Escolher mês',
    );
    if (!context.mounted) return;
    if (picked == null) return;

    setState(() {
      _period = PeriodFilter.month;
      _customStart = null;
      _customEnd = null;
      _month = DateTime(picked.year, picked.month, 1);
    });
    _recalcSummary();
  }

  Future<void> _openAdd(TxType type) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddTransactionPage(type: type)),
    );
    if (!mounted) return;
    if (saved == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transação salva ✅'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openEdit(TxItem tx) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditTransactionPage(tx: tx)),
    );
    if (!mounted) return;
    if (saved == true) await _load();
  }

  Future<void> _deleteTx(TxItem tx) async {
    if (tx.id == null) return;

    await _repo.delete(tx.id!);
    if (!mounted) return;
    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Transação excluída'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () async {
            await _repo.insert(
              TxItem(
                title: tx.title,
                amount: tx.amount,
                isIncome: tx.isIncome,
                date: tx.date,
                category: tx.category,
                note: tx.note,
                receiptImagePath: tx.receiptImagePath,
              ),
            );
            if (!mounted) return;
            await _load();
          },
        ),
      ),
    );
  }

  Future<void> _openFiltersSheet() async {
    final categories = _availableCategories();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        PeriodFilter p = _period;
        DateTime month = _month;
        DateTime? cs = _customStart;
        DateTime? ce = _customEnd;
        TxType? t = _type;
        String? cat = _category;

        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> pickMonthLocal() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: month,
                firstDate: DateTime(2015),
                lastDate: DateTime(2100),
              );
              if (!context.mounted) return;
              if (picked == null) return;
              setLocal(() => month = DateTime(picked.year, picked.month, 1));
            }

            Future<void> pickCustomLocal() async {
              final now = DateTime.now();
              final startInit = cs ?? _monthStart(now);
              final endInit = ce ?? now;

              final start = await showDatePicker(
                context: context,
                initialDate: startInit,
                firstDate: DateTime(2015),
                lastDate: DateTime(2100),
                helpText: 'Data inicial',
              );
              if (!context.mounted) return;
              if (start == null) return;

              final end = await showDatePicker(
                context: context,
                initialDate: endInit.isBefore(start) ? start : endInit,
                firstDate: start,
                lastDate: DateTime(2100),
                helpText: 'Data final',
              );
              if (!context.mounted) return;
              if (end == null) return;

              setLocal(() {
                cs = DateTime(start.year, start.month, start.day);
                ce = DateTime(end.year, end.month, end.day);
              });
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 6,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SheetHeader(
                      title: 'Filtros',
                      subtitle: 'Ajuste período, tipo e categoria',
                      onReset: () => setLocal(() {
                        p = PeriodFilter.month;
                        month = DateTime(
                          DateTime.now().year,
                          DateTime.now().month,
                          1,
                        );
                        cs = null;
                        ce = null;
                        t = null;
                        cat = null;
                      }),
                    ),
                    const SizedBox(height: 14),

                    _SectionTitle('Período'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('Mês'),
                          selected: p == PeriodFilter.month,
                          onSelected: (_) =>
                              setLocal(() => p = PeriodFilter.month),
                        ),
                        ChoiceChip(
                          label: const Text('Últimos 7 dias'),
                          selected: p == PeriodFilter.last7,
                          onSelected: (_) =>
                              setLocal(() => p = PeriodFilter.last7),
                        ),
                        ChoiceChip(
                          label: const Text('Personalizado'),
                          selected: p == PeriodFilter.custom,
                          onSelected: (_) =>
                              setLocal(() => p = PeriodFilter.custom),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (p == PeriodFilter.month)
                      _PickerTile(
                        title: 'Mês',
                        value: FormatBR.monthYear(month),
                        icon: Icons.calendar_month,
                        onTap: () async {
                          await pickMonthLocal();
                          setLocal(() {});
                        },
                      )
                    else if (p == PeriodFilter.custom)
                      _PickerTile(
                        title: 'Intervalo',
                        value: (cs != null && ce != null)
                            ? '${FormatBR.date(cs!)} • ${FormatBR.date(ce!)}'
                            : 'Escolher intervalo',
                        icon: Icons.date_range,
                        onTap: () async {
                          await pickCustomLocal();
                          setLocal(() {});
                        },
                      ),

                    const SizedBox(height: 16),
                    _SectionTitle('Tipo'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _SegChip(
                            label: 'Todos',
                            selected: t == null,
                            onTap: () => setLocal(() => t = null),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SegChip(
                            label: 'Receitas',
                            selected: t == TxType.income,
                            onTap: () => setLocal(() => t = TxType.income),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SegChip(
                            label: 'Despesas',
                            selected: t == TxType.expense,
                            onTap: () => setLocal(() => t = TxType.expense),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    _SectionTitle('Categoria'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: cat,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todas'),
                        ),
                        ...categories.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                      ],
                      onChanged: (v) => setLocal(() => cat = v),
                      decoration: _inputDeco('Categoria', Icons.category),
                    ),

                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              setState(() {
                                _period = p;
                                _month = month;
                                _customStart = cs;
                                _customEnd = ce;
                                _type = t;
                                _category = cat;
                              });
                              _recalcSummary();
                              Navigator.pop(context);
                            },
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAddSheet() async {
    final type = await showModalBottomSheet<TxType>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => const _AddTypeSheet(),
    );
    if (type == null) return;
    await _openAdd(type);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = _applyFilters(_all);
    final listForChart = _applyFiltersForChart(_all);
    final byCategory = _byCategoryForChart(listForChart);
    final selectedChartKey = (_category == null || _category!.trim().isEmpty)
        ? null
        : _category!.trim();

    final catLabel = (_category == null || _category!.trim().isEmpty)
        ? 'Todas'
        : _category!.trim();

    return Scaffold(
      backgroundColor: cs.surface,
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: cs.surface,
              surfaceTintColor: cs.surface,
              scrolledUnderElevation: 0,
              elevation: 0,
              titleSpacing: 16,
              title: const Text('Finanças'),
              actions: [
                IconButton(
                  tooltip: 'Filtros',
                  onPressed: _openFiltersSheet,
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  tooltip: 'Limpar filtros',
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
                IconButton(
                  tooltip: 'Investimentos',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InvestmentExtractPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.insights_rounded),
                ),
                const SizedBox(width: 6),
              ],
            ),

            // Resumo + navegação de mês (separado do AppBar para não sobrepor cliques)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    _SummaryHero(
                      saldo: _saldo,
                      income: _income,
                      expense: _expense,
                      period: _periodLabel(),
                      onTapSaldo: () => _scrollToTop(context),
                      onTapIncome: () => setState(() {
                        _type = TxType.income;
                        _recalcSummary();
                      }),
                      onTapExpense: () => setState(() {
                        _type = TxType.expense;
                        _recalcSummary();
                      }),
                    ),
                    const SizedBox(height: 10),
                    _MonthPager(
                      visible: _period == PeriodFilter.month,
                      monthLabel: FormatBR.monthYear(_month),
                      onPrev: () => _shiftMonth(-1),
                      onNext: () => _shiftMonth(1),
                      onPick: () => _pickMonthFromTop(context),
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const _ChartSkeletonCard()
                    else if (byCategory.isNotEmpty)
                      _CategoryChartCard(
                        byCategory: byCategory,
                        selectedKey: selectedChartKey,
                        type: _type,
                        onTapKey: _toggleCategoryFromChart,
                        onClear: () {
                          setState(() => _category = null);
                          _recalcSummary();
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Header fixo (pesquisa + atalhos de filtro)
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyHeaderDelegate(
                minExtent: 140,
                maxExtent: 140,
                builder: (context, shrinkOffset, overlaps) {
                  final showDivider = shrinkOffset > 0 || overlaps;
                  return Material(
                    color: cs.surface,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: showDivider
                                ? cs.outlineVariant.withOpacity(0.45)
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: Column(
                          children: [
                            _SearchBar(
                              controller: _searchCtrl,
                              hint: 'Buscar por título, nota ou categoria…',
                              onChanged: (_) => _recalcSummary(),
                              onClear: () {
                                _searchCtrl.clear();
                                _recalcSummary();
                              },
                            ),
                            const SizedBox(height: 10),
                            _QuickFiltersRow(
                              periodLabel: _periodLabel(),
                              typeLabel: _typeLabel(),
                              categoryLabel: catLabel,
                              onTapPeriod: _openFiltersSheet,
                              onTapType: _openFiltersSheet,
                              onTapCategory: _openFiltersSheet,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            if (_loading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList.separated(
                  itemCount: 7,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => const _SkeletonTxCard(),
                ),
              )
            else if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  onAdd: _openAddSheet,
                  onFilters: _openFiltersSheet,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final tx = list[index];
                    final key = ValueKey(
                      tx.id ?? '${tx.date.millisecondsSinceEpoch}-$index',
                    );

                    return Dismissible(
                      key: key,
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        return await _showDeleteConfirm(tx);
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: cs.errorContainer,
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: cs.onErrorContainer,
                        ),
                      ),
                      child: _PremiumTxCard(
                        tx: tx,
                        onTap: () => _openEdit(tx),
                        onDelete: () async {
                          await _showDeleteConfirm(tx);
                        },
                      ),
                    );
                  },
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo'),
      ),
    );
  }

  void _scrollToTop(BuildContext context) {
    // Só uma UX: tocar no saldo leva o usuário pro topo (sem quebrar nada).
    // CustomScrollView usa PrimaryScrollController automaticamente.
    final controller = PrimaryScrollController.of(context);
    if (!controller.hasClients) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<bool> _showDeleteConfirm(TxItem tx) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir transação?'),
        content: Text(
          '“${tx.title}” será removida. Você poderá desfazer no snackbar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteTx(tx);
      return true;
    }
    return false;
  }
}

class _CatMeta {
  final String name;
  final IconData icon;
  final Color color;
  const _CatMeta({required this.name, required this.icon, required this.color});
}

_CatMeta _catMeta(BuildContext context, String raw) {
  final cs = Theme.of(context).colorScheme;
  final name = raw.trim().isEmpty ? 'Sem categoria' : raw.trim();
  final k = name.toLowerCase();

  IconData icon = Icons.category_rounded;
  Color color = cs.primary;

  bool has(String s) => k.contains(s);

  if (has('merc') || has('super') || has('feira')) {
    icon = Icons.shopping_cart_rounded;
    color = cs.tertiary;
  } else if (has('combust') || has('gas') || has('posto') || has('transp')) {
    icon = Icons.local_gas_station_rounded;
    color = cs.secondary;
  } else if (has('casa') ||
      has('alug') ||
      has('condom') ||
      has('energia') ||
      has('água') ||
      has('agua')) {
    icon = Icons.home_rounded;
    color = cs.primary;
  } else if (has('saúde') ||
      has('saude') ||
      has('farm') ||
      has('méd') ||
      has('med')) {
    icon = Icons.health_and_safety_rounded;
    color = cs.error;
  } else if (has('lazer') || has('rest') || has('bar') || has('cinema')) {
    icon = Icons.local_activity_rounded;
    color = cs.secondary;
  } else if (has('sal') || has('pag') || has('trabalho')) {
    icon = Icons.payments_rounded;
    color = cs.primary;
  } else if (has('invest') || has('ação') || has('acao') || has('fi')) {
    icon = Icons.trending_up_rounded;
    color = cs.tertiary;
  } else if (has('educ') || has('curso') || has('livro')) {
    icon = Icons.school_rounded;
    color = cs.primary;
  }

  return _CatMeta(name: name, icon: icon, color: color);
}

InputDecoration _inputDeco(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    filled: true,
  );
}

class _SummaryHero extends StatelessWidget {
  final double saldo;
  final double income;
  final double expense;
  final String period;
  final VoidCallback onTapSaldo;
  final VoidCallback onTapIncome;
  final VoidCallback onTapExpense;

  const _SummaryHero({
    required this.saldo,
    required this.income,
    required this.expense,
    required this.period,
    required this.onTapSaldo,
    required this.onTapIncome,
    required this.onTapExpense,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTapSaldo,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_graph_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      period,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Saldo',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                FormatBR.money(saldo),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Receitas',
                      value: FormatBR.money(income),
                      icon: Icons.arrow_upward_rounded,
                      tone: cs.primary,
                      onTap: onTapIncome,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                      label: 'Despesas',
                      value: FormatBR.money(expense),
                      icon: Icons.arrow_downward_rounded,
                      tone: cs.error,
                      onTap: onTapExpense,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tone;
  final VoidCallback onTap;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tone.withOpacity(0.10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tone.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final hasText = value.text.trim().isNotEmpty;
          return TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: hasText
                  ? IconButton(
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
            ),
          );
        },
      ),
    );
  }
}

class _QuickFiltersRow extends StatelessWidget {
  final String periodLabel;
  final String typeLabel;
  final String categoryLabel;
  final VoidCallback onTapPeriod;
  final VoidCallback onTapType;
  final VoidCallback onTapCategory;

  const _QuickFiltersRow({
    required this.periodLabel,
    required this.typeLabel,
    required this.categoryLabel,
    required this.onTapPeriod,
    required this.onTapType,
    required this.onTapCategory,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _FilterPill(
            icon: Icons.calendar_month_rounded,
            label: periodLabel,
            onTap: onTapPeriod,
          ),
          const SizedBox(width: 10),
          _FilterPill(
            icon: Icons.swap_vert_rounded,
            label: typeLabel,
            onTap: onTapType,
          ),
          const SizedBox(width: 10),
          _FilterPill(
            icon: Icons.sell_rounded,
            label: categoryLabel,
            onTap: onTapCategory,
          ),
        ],
      ),
    );
  }
}

class _MonthPager extends StatelessWidget {
  final bool visible;
  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  const _MonthPager({
    required this.visible,
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mês anterior',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        monthLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Próximo mês',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FilterPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumTxCard extends StatelessWidget {
  final TxItem tx;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PremiumTxCard({
    required this.tx,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = _catMeta(context, tx.category);
    final isIncome = tx.isIncome;
    final accent = isIncome ? cs.primary : cs.error;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: meta.color.withOpacity(0.12),
                ),
                child: Icon(meta.icon, color: meta.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${FormatBR.date(tx.date)} • ${meta.name}${(tx.receiptImagePath != null) ? '  •  📷' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if ((tx.note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        tx.note!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    (isIncome ? '+' : '-') + FormatBR.money(tx.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    tooltip: 'Excluir',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onFilters;

  const _EmptyState({required this.onAdd, required this.onFilters});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 54, color: cs.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              'Nada por aqui',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Crie sua primeira transação ou ajuste os filtros.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Adicionar'),
                ),
                OutlinedButton.icon(
                  onPressed: onFilters,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Filtros'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTypeSheet extends StatelessWidget {
  const _AddTypeSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Novo lançamento',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Escolha o tipo para continuar',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _SheetAction(
              icon: Icons.arrow_upward_rounded,
              title: 'Receita',
              subtitle: 'Entradas, salários, reembolsos…',
              onTap: () => Navigator.pop(context, TxType.income),
            ),
            const SizedBox(height: 10),
            _SheetAction(
              icon: Icons.arrow_downward_rounded,
              title: 'Despesa',
              subtitle: 'Compras, contas, combustível…',
              onTap: () => Navigator.pop(context, TxType.expense),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onReset;

  const _SheetHeader({
    required this.title,
    required this.subtitle,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Reset'),
        ),
      ],
    );
  }
}

class _SegChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? cs.onPrimary : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _StickyHeaderBuilder =
    Widget Function(
      BuildContext context,
      double shrinkOffset,
      bool overlapsContent,
    );

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double _min;
  final double _max;
  final _StickyHeaderBuilder builder;

  _StickyHeaderDelegate({
    required double minExtent,
    required double maxExtent,
    required this.builder,
  }) : _min = minExtent,
       _max = maxExtent;

  @override
  double get minExtent => _min;

  @override
  double get maxExtent => _max;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return builder(context, shrinkOffset, overlapsContent);
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return _min != oldDelegate._min ||
        _max != oldDelegate._max ||
        builder != oldDelegate.builder;
  }
}

class _SkeletonTxCard extends StatelessWidget {
  const _SkeletonTxCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.65),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 12,
                    width: 170,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 18,
              width: 84,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.60),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Premium chart card (Home) — baseado no estilo do InvestmentExtractPage
// -----------------------------------------------------------------------------
class _CategoryChartCard extends StatelessWidget {
  final Map<String, double> byCategory;
  final String? selectedKey;
  final TxType? type;
  final ValueChanged<String> onTapKey;
  final VoidCallback onClear;

  const _CategoryChartCard({
    required this.byCategory,
    required this.selectedKey,
    required this.type,
    required this.onTapKey,
    required this.onClear,
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (byCategory.isEmpty) return const SizedBox.shrink();

    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = entries.fold<double>(0, (p, e) => p + e.value);

    final colorsByKey = <String, Color>{};
    for (final e in entries) {
      colorsByKey[e.key] = _ChartColors.forKey(cs, e.key);
    }

    final bool hasSelection =
        selectedKey != null && selectedKey!.trim().isNotEmpty;

    final String title = 'Distribuição por categoria';
    final String subtitle = type == null
        ? 'Movimentação (receitas + despesas)'
        : (type == TxType.income ? 'Somente receitas' : 'Somente despesas');

    final double selectedValue = hasSelection
        ? (byCategory[selectedKey] ?? 0)
        : total;

    final centerLabel = hasSelection
        ? 'Selecionado'
        : (type == null
              ? 'Total'
              : (type == TxType.income ? 'Receitas' : 'Despesas'));

    final centerValue = FormatBR.money(selectedValue);

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_rounded, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasSelection)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Limpar'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 144,
                  height: 144,
                  child: _DonutChart(
                    entries: entries,
                    total: total <= 0 ? 1 : total,
                    selectedKey: selectedKey,
                    colorsByKey: colorsByKey,
                    centerLabel: centerLabel,
                    centerValue: centerValue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (final e in entries.take(6))
                        _AllocRow(
                          label: e.key,
                          value: e.value,
                          total: total,
                          money: FormatBR.money,
                          color: colorsByKey[e.key]!,
                          selected:
                              hasSelection &&
                              _norm(selectedKey!) == _norm(e.key),
                          onTap: () => onTapKey(e.key),
                        ),
                      if (entries.length > 6)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '+${entries.length - 6} categorias…',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
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
}

class _AllocRow extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final String Function(double) money;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AllocRow({
    required this.label,
    required this.value,
    required this.total,
    required this.money,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = total <= 0 ? 0.0 : (value / total);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? cs.onPrimaryContainer : cs.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartColors {
  static Color forKey(ColorScheme cs, String key) {
    // Mesmo "DNA" do InvestmentExtractPage: cores fortes via HSL,
    // mas com distribuição estável por chave.
    final base = HSLColor.fromColor(cs.primary);
    final sat = math.max(0.58, base.saturation);
    final light = cs.brightness == Brightness.dark ? 0.55 : 0.45;

    final hue = (base.hue + _hashToHue(key)) % 360.0;
    return HSLColor.fromAHSL(1.0, hue, sat, light).toColor();
  }

  static double _hashToHue(String s) {
    // FNV-1a 32-bit
    var hash = 0x811c9dc5;
    final str = s.toLowerCase().trim();
    for (var i = 0; i < str.length; i++) {
      hash ^= str.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return (hash % 360).toDouble();
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                  color: Colors.black.withOpacity(0.08),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  centerLabel,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
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
      ..color = colorScheme.surfaceContainerHighest;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringRadius),
      -math.pi / 2,
      2 * math.pi,
      false,
      bg,
    );

    if (entries.isEmpty || total <= 0) return;

    final gap = 0.03; // small gap between segments
    var start = -math.pi / 2;

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

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        start,
        drawSweep,
        false,
        paint,
      );

      start += sweep;
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

class _ChartSkeletonCard extends StatelessWidget {
  const _ChartSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.65),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      height: 44,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
