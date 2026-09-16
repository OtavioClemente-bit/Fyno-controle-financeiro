import 'package:flutter/material.dart';

import '../../shared/format/format_br.dart';
import 'savings_goals_repository.dart';

class SavingsGoalsPage extends StatefulWidget {
  const SavingsGoalsPage({super.key});

  @override
  State<SavingsGoalsPage> createState() => _SavingsGoalsPageState();
}

class _SavingsGoalsPageState extends State<SavingsGoalsPage> {
  final _repository = SavingsGoalsRepository();
  List<SavingsGoal> _goals = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final goals = await _repository.getAll();
    if (mounted) {
      setState(() {
        _goals = goals;
        _loading = false;
      });
    }
  }

  double _number(String text) =>
      double.tryParse(text.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  IconData _icon(String key) => switch (key) {
    'travel' => Icons.flight_takeoff_rounded,
    'home' => Icons.home_rounded,
    'car' => Icons.directions_car_rounded,
    'reserve' => Icons.shield_rounded,
    _ => Icons.shopping_bag_rounded,
  };

  Future<void> _newGoal() async {
    var name = '';
    var amount = '';
    var saved = '';
    var icon = 'travel';
    DateTime? deadline;
    String? error;
    final goal = await showModalBottomSheet<SavingsGoal>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Criar uma meta',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Dê um propósito ao dinheiro que você quer guardar.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nome da meta',
                    prefixIcon: Icon(Icons.flag_rounded),
                  ),
                  onChanged: (value) => name = value,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor da meta',
                          prefixText: 'R\$ ',
                        ),
                        onChanged: (value) => amount = value,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Já guardado',
                          prefixText: 'R\$ ',
                        ),
                        onChanged: (value) => saved = value,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: icon,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de objetivo',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'travel', child: Text('Viagem')),
                    DropdownMenuItem(
                      value: 'shopping',
                      child: Text('Comprar algo'),
                    ),
                    DropdownMenuItem(
                      value: 'reserve',
                      child: Text('Reserva de emergência'),
                    ),
                    DropdownMenuItem(value: 'home', child: Text('Casa')),
                    DropdownMenuItem(value: 'car', child: Text('Veículo')),
                  ],
                  onChanged: (value) => icon = value ?? icon,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded),
                  label: Text(
                    deadline == null
                        ? 'Adicionar prazo (opcional)'
                        : 'Prazo: ${deadline!.day}/${deadline!.month}/${deadline!.year}',
                  ),
                  onPressed: () async {
                    final value = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(DateTime.now().year + 20),
                      initialDate:
                          deadline ??
                          DateTime.now().add(const Duration(days: 180)),
                    );
                    if (value != null) setLocal(() => deadline = value);
                  },
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () {
                    if (name.trim().isEmpty || _number(amount) <= 0) {
                      setLocal(
                        () =>
                            error = 'Informe o nome e um valor maior que zero.',
                      );
                      return;
                    }
                    Navigator.pop(
                      sheetContext,
                      SavingsGoal(
                        name: name.trim(),
                        targetAmount: _number(amount),
                        savedAmount: _number(saved),
                        deadline: deadline,
                        iconKey: icon,
                        colorValue: 0xFF167D64,
                      ),
                    );
                  },
                  child: const Text('Criar meta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (goal != null) {
      await _repository.create(goal);
      await _load();
    }
  }

  Future<void> _contribute(SavingsGoal goal) async {
    var amount = '';
    var note = '';
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Guardar para ${goal.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
              ),
              onChanged: (text) => amount = text,
            ),
            const SizedBox(height: 12),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
              ),
              onChanged: (text) => note = text,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, _number(amount)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (value != null && value > 0 && goal.id != null) {
      await _repository.contribute(goal.id!, value, note: note);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final saved = _goals.fold(0.0, (sum, goal) => sum + goal.savedAmount);
    final target = _goals.fold(0.0, (sum, goal) => sum + goal.targetAmount);
    return Scaffold(
      appBar: AppBar(title: const Text('Metas e sonhos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newGoal,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova meta'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Seus planos ganhando forma',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: cs.onPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          FormatBR.money(saved),
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          target == 0
                              ? 'Crie sua primeira meta'
                              : 'guardados de ${FormatBR.money(target)}',
                          style: TextStyle(
                            color: cs.onPrimary.withValues(alpha: .82),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_goals.isEmpty)
                    Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.savings_rounded,
                              size: 46,
                              color: cs.primary,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Transforme um plano em uma meta',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Viagem, compra ou reserva: acompanhe cada valor guardado.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._goals.map(
                      (goal) => _GoalCard(
                        goal: goal,
                        icon: _icon(goal.iconKey),
                        onContribute: () => _contribute(goal),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.icon,
    required this.onContribute,
  });
  final SavingsGoal goal;
  final IconData icon;
  final VoidCallback onContribute;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        goal.completed
                            ? 'Meta alcançada!'
                            : 'Faltam ${FormatBR.money(goal.remaining)}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(goal.progress * 100).round()}%',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            LinearProgressIndicator(
              value: goal.progress,
              minHeight: 9,
              borderRadius: BorderRadius.circular(99),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${FormatBR.money(goal.savedAmount)} de ${FormatBR.money(goal.targetAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!goal.completed)
                  TextButton.icon(
                    onPressed: onContribute,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Guardar'),
                  ),
              ],
            ),
            if (goal.deadline != null)
              Text(
                'Prazo: ${goal.deadline!.day}/${goal.deadline!.month}/${goal.deadline!.year}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
