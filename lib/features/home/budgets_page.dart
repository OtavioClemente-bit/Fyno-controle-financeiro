import 'package:flutter/material.dart';

import '../../core/db/app_db.dart';
import '../../shared/format/format_br.dart';
import '../../shared/widgets/category_picker_field.dart';
import 'budget_repository.dart';
import 'finance_visuals.dart';

class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  final _repository = BudgetRepository();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  List<BudgetProgress> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repository.getProgress(_month);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _loading = true;
    });
    await _load();
  }

  Future<void> _edit([MonthlyBudget? current]) async {
    final customCategories = await AppDb.getCategoryNames();
    const defaults = [
      'Alimentação',
      'Combustível',
      'Contas',
      'Educação',
      'Lazer',
      'Mercado',
      'Moradia',
      'Saúde',
      'Transporte',
      'Assinaturas',
      'Outros',
    ];
    final categories = {
      ...defaults,
      ...customCategories,
      if (current != null) current.category,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    var category = current?.category ?? categories.first;
    var amount = current == null
        ? ''
        : current.amount.toStringAsFixed(2).replaceAll('.', ',');
    var warning = current?.warningPercent ?? 80;
    String? error;
    if (!mounted) return;
    final result = await showDialog<MonthlyBudget>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: EdgeInsets.fromLTRB(
            18,
            24,
            18,
            24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Text(current == null ? 'Novo orçamento' : 'Editar orçamento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CategoryPickerField(
                  value: category,
                  items: categories,
                  enabled: current == null,
                  onChanged: (value) => setDialogState(() => category = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: amount,
                  onChanged: (value) => amount = value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Limite mensal (R\$)',
                    hintText: 'Ex: 600,00',
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Avisar ao atingir $warning%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Slider(
                  value: warning.toDouble(),
                  min: 50,
                  max: 100,
                  divisions: 10,
                  label: '$warning%',
                  onChanged: (value) =>
                      setDialogState(() => warning = value.round()),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final value =
                    double.tryParse(
                      amount.replaceAll('.', '').replaceAll(',', '.'),
                    ) ??
                    0;
                if (value <= 0) {
                  setDialogState(
                    () => error = 'Informe um limite maior que zero.',
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  MonthlyBudget(
                    id: current?.id,
                    category: category,
                    amount: value,
                    warningPercent: warning,
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _repository.save(result);
    await _load();
  }

  Future<void> _archive(MonthlyBudget item) async {
    if (item.id == null) return;
    await _repository.archive(item.id!);
    await _load();
  }

  String _monthName(int value) => const [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ][value - 1];

  @override
  Widget build(BuildContext context) {
    final totalLimit = _items.fold<double>(
      0,
      (sum, item) => sum + item.budget.amount,
    );
    final totalSpent = _items.fold<double>(0, (sum, item) => sum + item.spent);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orçamentos mensais'),
        actions: [
          IconButton(
            onPressed: _edit,
            tooltip: 'Novo orçamento',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add_chart_rounded),
        label: const Text('Criar orçamento'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${_monthName(_month.month)} de ${_month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Visão geral',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${FormatBR.money(totalSpent)} de ${FormatBR.money(totalLimit)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          totalLimit == 0
                              ? 'Crie seu primeiro limite mensal'
                              : '${FormatBR.money(totalLimit - totalSpent)} disponíveis no planejamento',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Icon(Icons.donut_large_rounded, size: 50),
                        SizedBox(height: 12),
                        Text(
                          'Defina quanto deseja gastar em cada categoria. As despesas do extrato serão somadas automaticamente.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ..._items.map(
                    (item) => _BudgetCard(
                      progress: item,
                      onEdit: () => _edit(item.budget),
                      onArchive: () => _archive(item.budget),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.progress,
    required this.onEdit,
    required this.onArchive,
  });
  final BudgetProgress progress;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = progress.ratio;
    final warningRatio = progress.budget.warningPercent / 100;
    final color = progress.exceeded
        ? cs.error
        : ratio >= warningRatio
        ? Colors.orange.shade700
        : cs.primary;
    final status = progress.exceeded
        ? 'Limite ultrapassado em ${FormatBR.money(-progress.remaining)}'
        : ratio >= warningRatio
        ? 'Atenção: restam ${FormatBR.money(progress.remaining)}'
        : 'Ainda restam ${FormatBR.money(progress.remaining)}';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .14),
                  child: Icon(
                    financeCategoryIcon(progress.budget.category),
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        progress.budget.category,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${FormatBR.money(progress.spent)} de ${FormatBR.money(progress.budget.amount)}',
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onArchive(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar limite')),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text('Remover orçamento'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 10,
              borderRadius: BorderRadius.circular(99),
              color: color,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
