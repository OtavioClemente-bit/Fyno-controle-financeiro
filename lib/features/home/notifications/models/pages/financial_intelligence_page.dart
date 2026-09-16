import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../../core/db/app_db.dart';
import '../../../models/tx_item.dart';
import '../recurring_transaction_detector.dart';
import '../repositories/smart_rules_repository.dart';
import '../smart_transaction_rule.dart';

class FinancialIntelligencePage extends StatefulWidget {
  const FinancialIntelligencePage({super.key});

  @override
  State<FinancialIntelligencePage> createState() =>
      _FinancialIntelligencePageState();
}

class _FinancialIntelligencePageState extends State<FinancialIntelligencePage> {
  final _rulesRepo = SmartRulesRepository();
  bool _loading = true;
  List<RecurringTransactionCandidate> _recurrences = const [];
  List<SmartTransactionRule> _rules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDb.instance;
    final txRows = await db.query('transactions', orderBy: 'date_ms ASC');
    final ignoredRows = await db.query(
      'recurring_preferences',
      columns: const ['recurrence_key'],
      where: 'ignored = 1',
    );
    final ignored = ignoredRows
        .map((row) => row['recurrence_key'] as String)
        .toSet();
    final detected = RecurringTransactionDetector.detect(
      txRows.map(TxItem.fromMap).toList(),
    ).where((item) => !ignored.contains(item.key)).toList(growable: false);
    final rules = await _rulesRepo.getAll();
    if (!mounted) return;
    setState(() {
      _recurrences = detected;
      _rules = rules;
      _loading = false;
    });
  }

  Future<void> _ignore(RecurringTransactionCandidate item) async {
    final db = await AppDb.instance;
    await db.insert('recurring_preferences', {
      'recurrence_key': item.key,
      'ignored': 1,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _load();
  }

  Future<void> _deleteRule(SmartTransactionRule rule) async {
    if (rule.id == null) return;
    await _rulesRepo.delete(rule.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Inteligência financeira'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Recorrências'),
            Tab(text: 'Regras aprendidas'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                _RecurringList(items: _recurrences, onIgnore: _ignore),
                _RulesList(items: _rules, onDelete: _deleteRule),
              ],
            ),
    ),
  );
}

class _RecurringList extends StatelessWidget {
  const _RecurringList({required this.items, required this.onIgnore});
  final List<RecurringTransactionCandidate> items;
  final ValueChanged<RecurringTransactionCandidate> onIgnore;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyIntelligence(
        icon: Icons.repeat_rounded,
        title: 'Analisando seus padrões',
        text:
            'Depois de pelo menos duas cobranças parecidas, assinaturas e contas recorrentes aparecem aqui.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final cadence = switch (item.cadence) {
          RecurrenceCadence.weekly => 'semanal',
          RecurrenceCadence.monthly => 'mensal',
          RecurrenceCadence.yearly => 'anual',
        };
        return Card(
          elevation: 0,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            leading: CircleAvatar(
              child: Icon(
                item.isSubscription
                    ? Icons.subscriptions_rounded
                    : Icons.receipt_long_rounded,
              ),
            ),
            title: Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${item.isSubscription ? 'Possível assinatura' : 'Conta recorrente'} • $cadence\nPróxima estimativa: ${DateFormat('dd/MM').format(item.nextExpectedDate)} • ${item.occurrences} ocorrências',
            ),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (_) => onIgnore(item),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ignore', child: Text('Não é recorrente')),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RulesList extends StatelessWidget {
  const _RulesList({required this.items, required this.onDelete});
  final List<SmartTransactionRule> items;
  final ValueChanged<SmartTransactionRule> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyIntelligence(
        icon: Icons.psychology_alt_rounded,
        title: 'O Fyno aprende com você',
        text:
            'Ao confirmar ou corrigir uma movimentação detectada, título, categoria e pagamento ficam aprendidos neste aparelho.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final rule = items[index];
        return Card(
          elevation: 0,
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.auto_awesome_rounded),
            ),
            title: Text(
              rule.merchantName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${rule.title} • ${rule.category}\nUsada ${rule.useCount} vez(es) • dados somente no aparelho',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Esquecer regra',
              onPressed: () => onDelete(rule),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyIntelligence extends StatelessWidget {
  const _EmptyIntelligence({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 32, child: Icon(icon, size: 32)),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
