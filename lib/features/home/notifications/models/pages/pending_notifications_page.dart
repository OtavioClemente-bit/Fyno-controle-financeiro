import 'package:flutter/material.dart';

import '../repositories/notification_import_repository.dart';
import '../pending_notification.dart';

import '../../../models/tx_type.dart';
import '../../../add_transaction_page.dart';

class PendingNotificationsPage extends StatefulWidget {
  const PendingNotificationsPage({super.key});

  @override
  State<PendingNotificationsPage> createState() =>
      _PendingNotificationsPageState();
}

class _PendingNotificationsPageState extends State<PendingNotificationsPage> {
  final NotificationImportRepository _repo = NotificationImportRepository();

  late Future<List<PendingNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getPending();
  }

  Future<void> _refresh() async {
    setState(() => _future = _repo.getPending());
  }

  Future<void> _ignore(PendingNotification n) async {
    await _repo.markIgnored(n.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ignorado.')));
    await _refresh();
  }

  Future<void> _convert(PendingNotification n, {required bool isIncome}) async {
    // Abre AddTransactionPage e deixa o usuário confirmar/editar (categoria, obs, etc).
    // Para manter compatibilidade com versões diferentes, enviamos só o tipo.
    // Se sua AddTransactionPage tiver prefill*, ela vai usar; se não tiver, só abre normal.
    final txType = isIncome ? TxType.income : TxType.expense;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTransactionPage(
          type: txType,
          // ignore: invalid_named_parameter, unused_named_parameter
          prefillTitle: (n.title ?? '').trim().isNotEmpty
              ? (n.title ?? '').trim()
              : n.packageName,
          // ignore: invalid_named_parameter, unused_named_parameter
          prefillNote: (n.text ?? '').trim(),
          // ignore: invalid_named_parameter, unused_named_parameter
          prefillAmount: n.parsedAmount,
          // ignore: invalid_named_parameter, unused_named_parameter
          prefillDateMs: n.postedAtMs,
        ),
      ),
    );

    if (saved == true) {
      await _repo.markImported(n.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isIncome ? 'Receita criada ✅' : 'Despesa criada ✅'),
        ),
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Caixa de entrada')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<PendingNotification>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? const <PendingNotification>[];

            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 40),
                  Center(child: Text('Nenhuma notificação pendente.')),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final n = items[i];
                final title = (n.title ?? '').trim();
                final text = (n.text ?? '').trim();
                final showTitle = title.isNotEmpty
                    ? title
                    : (n.packageName.isNotEmpty
                          ? n.packageName
                          : '(sem título)');
                final showText = text.isNotEmpty ? text : '(vazio)';
                final when = _fmtWhen(n.postedAtMs);

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          showTitle,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(showText),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${n.packageName} • $when',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ignorar',
                              onPressed: () => _ignore(n),
                              icon: const Icon(Icons.hide_source),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _convert(n, isIncome: false),
                                icon: const Icon(Icons.remove_circle_outline),
                                label: const Text('Despesa'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _convert(n, isIncome: true),
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('Receita'),
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
        ),
      ),
    );
  }

  String _fmtWhen(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${hh}:$mi';
  }
}
