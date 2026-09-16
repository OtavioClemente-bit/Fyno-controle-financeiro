import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../add_transaction_page.dart';
import '../../../models/tx_type.dart';
import '../../../models/tx_item.dart';
import '../bank_app_catalog.dart';
import '../notification_bridge.dart';
import '../notification_inbox_service.dart';
import '../pending_notification.dart';
import '../repositories/notification_import_repository.dart';
import '../repositories/smart_rules_repository.dart';
import '../transaction_category_suggester.dart';

enum _InboxFilter { review, reminders, all }

class PendingNotificationsPage extends StatefulWidget {
  const PendingNotificationsPage({super.key});

  @override
  State<PendingNotificationsPage> createState() =>
      _PendingNotificationsPageState();
}

class _PendingNotificationsPageState extends State<PendingNotificationsPage> {
  final _repo = NotificationImportRepository();
  final _inboxService = NotificationInboxService();
  final _rules = SmartRulesRepository();
  final _searchController = TextEditingController();
  Timer? _syncTimer;
  bool _refreshing = false;
  bool _loading = true;
  List<PendingNotification> _items = const [];
  _InboxFilter _filter = _InboxFilter.review;
  String _query = '';

  int get _reviewCount =>
      _items.where((item) => item.status == 'pending').length;
  int get _reminderCount =>
      _items.where((item) => item.status == 'snoozed').length;

  @override
  void initState() {
    super.initState();
    _refresh();
    _syncTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refresh(showLoading: false),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool showLoading = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      await _inboxService.sync();
      final items = await _repo.getPending();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.inbox_outlined),
        title: const Text('Organizar tudo como ignorado?'),
        content: const Text(
          'Os itens sairão da caixa de entrada, mas o histórico será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Organizar caixa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final item in _items) {
      final id = item.id;
      if (id != null && item.hasReminder) {
        await NotificationBridge.instance.cancelReviewReminder(id);
      }
    }
    await _repo.clearPending();
    await NotificationBridge.instance.clearBufferedNotifications();
    await _refresh(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Caixa de entrada organizada.')),
    );
  }

  Future<void> _ignore(PendingNotification item) async {
    final id = item.id;
    if (id == null) return;
    if (item.hasReminder) {
      await NotificationBridge.instance.cancelReviewReminder(id);
    }
    await _repo.ignore(id);
    await _refresh(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Movimentação ignorada.'),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () async {
            await _repo.bringBackNow(id);
            await _refresh(showLoading: false);
          },
        ),
      ),
    );
  }

  Future<void> _reviewNow(PendingNotification item) async {
    final id = item.id;
    if (id == null) return;
    if (item.hasReminder) {
      await NotificationBridge.instance.cancelReviewReminder(id);
    }
    await _repo.bringBackNow(id);
    await _refresh(showLoading: false);
  }

  Future<void> _convert(
    PendingNotification item, {
    required bool isIncome,
  }) async {
    final id = item.id;
    final learned = await _rules.findFor(item.title, item.text);
    if (!mounted) return;
    TxItem? savedTransaction;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTransactionPage(
          type: (learned?.isIncome ?? isIncome)
              ? TxType.income
              : TxType.expense,
          prefillTitle: learned?.title ?? _bestTitle(item, isIncome: isIncome),
          prefillNote: item.text.trim().isEmpty ? null : item.text.trim(),
          prefillAmount: item.parsedAmount,
          prefillDateMs: item.postedAtMs,
          prefillPaymentMethod: learned?.paymentMethod ?? item.parsedMethod,
          prefillCategory:
              learned?.category ?? _categoryFor(item, isIncome: isIncome),
          onSaved: (transaction) => savedTransaction = transaction,
        ),
      ),
    );
    if (saved != true || id == null) return;
    if (savedTransaction != null) {
      await _rules.learn(
        notificationTitle: item.title,
        notificationText: item.text,
        transaction: savedTransaction!,
      );
    }
    await NotificationBridge.instance.cancelReviewReminder(id);
    await _repo.markImported(id);
    await _refresh(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isIncome
              ? 'Receita organizada com sucesso.'
              : 'Despesa organizada com sucesso.',
        ),
      ),
    );
  }

  Future<void> _scheduleReminder(PendingNotification item) async {
    final id = item.id;
    if (id == null) return;
    final when = await _showReminderPicker(item.reminderAtMs);
    if (when == null || !mounted) return;
    var permissionGranted = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      permissionGranted = (await Permission.notification.request()).isGranted;
    }
    await _repo.snooze(id, when);
    final scheduled = await NotificationBridge.instance.scheduleReviewReminder(
      notificationId: id,
      at: when,
      bankName: bankByPackage(item.packageName)?.name ?? 'seu banco',
      amount: item.parsedAmount,
    );
    await _refresh(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          permissionGranted && scheduled
              ? 'Lembrete agendado para ${_formatReminder(when)}.'
              : 'Lembrete salvo no Fyno. Ative as notificações para receber o aviso.',
        ),
      ),
    );
  }

  Future<DateTime?> _showReminderPicker(int? currentAtMs) async {
    final now = DateTime.now();
    final inOneHour = now.add(const Duration(hours: 1));
    var tonight = DateTime(now.year, now.month, now.day, 19);
    if (!tonight.isAfter(now)) {
      tonight = DateTime(now.year, now.month, now.day + 1, 9);
    }
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    return showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lembrar de revisar',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'O Fyno separa esta movimentação e avisa no momento escolhido.',
              style: TextStyle(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _ReminderOption(
              icon: Icons.schedule_rounded,
              title: 'Daqui a 1 hora',
              subtitle: _formatReminder(inOneHour),
              onTap: () => Navigator.pop(sheetContext, inOneHour),
            ),
            _ReminderOption(
              icon: Icons.dark_mode_outlined,
              title: tonight.hour == 19 ? 'Hoje à noite' : 'Amanhã cedo',
              subtitle: _formatReminder(tonight),
              onTap: () => Navigator.pop(sheetContext, tonight),
            ),
            if (tomorrow != tonight)
              _ReminderOption(
                icon: Icons.wb_sunny_outlined,
                title: 'Amanhã cedo',
                subtitle: _formatReminder(tomorrow),
                onTap: () => Navigator.pop(sheetContext, tomorrow),
              ),
            _ReminderOption(
              icon: Icons.calendar_month_outlined,
              title: 'Escolher data e hora',
              subtitle: currentAtMs == null
                  ? 'Defina o melhor momento'
                  : 'Atual: ${_formatReminder(DateTime.fromMillisecondsSinceEpoch(currentAtMs))}',
              onTap: () async {
                final custom = await _pickCustomReminder(
                  currentAtMs == null
                      ? tomorrow
                      : DateTime.fromMillisecondsSinceEpoch(currentAtMs),
                );
                if (custom != null && sheetContext.mounted) {
                  Navigator.pop(sheetContext, custom);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickCustomReminder(DateTime initial) async {
    final now = DateTime.now();
    final start = initial.isAfter(now)
        ? initial
        : now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null) return null;
    final result = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (result.isAfter(now)) return result;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha um horário futuro.')),
      );
    }
    return null;
  }

  String _categoryFor(PendingNotification item, {bool? isIncome}) {
    final stored = item.suggestedCategory?.trim();
    if (stored != null &&
        stored.isNotEmpty &&
        isIncome == item.parsedIsIncome) {
      return stored;
    }
    return TransactionCategorySuggester.suggest(
      text: '${item.title} ${item.text}',
      isIncome: isIncome ?? item.parsedIsIncome,
    ).category;
  }

  String _bestTitle(PendingNotification item, {required bool isIncome}) {
    final bank = bankByPackage(item.packageName)?.name ?? 'Banco';
    final method = _methodLabel(item.parsedMethod);
    if (isIncome) {
      return method == 'transação'
          ? 'Valor recebido — $bank'
          : '$method recebido — $bank';
    }
    return method == 'transação'
        ? 'Compra — $bank'
        : 'Compra no $method — $bank';
  }

  String _methodLabel(String? method) {
    return switch (method?.trim().toLowerCase()) {
      'pix' => 'Pix',
      'debit' || 'débito' => 'débito',
      'credit' || 'crédito' => 'crédito',
      'cash' || 'dinheiro' => 'dinheiro',
      'transferência' => 'transferência',
      _ => 'transação',
    };
  }

  String _formatMoney(double? amount) {
    if (amount == null) return 'Valor para confirmar';
    final parts = amount.toStringAsFixed(2).split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return 'R\$ $integer,${parts.last}';
  }

  String _formatReminder(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final prefix = day == today
        ? 'hoje'
        : day == today.add(const Duration(days: 1))
        ? 'amanhã'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    return '$prefix às ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatPostedAt(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'agora';
    if (difference.inHours < 1) return 'há ${difference.inMinutes} min';
    if (difference.inDays < 1) return 'há ${difference.inHours} h';
    if (difference.inDays == 1) return 'ontem';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  List<PendingNotification> get _visibleItems {
    Iterable<PendingNotification> visible = _items;
    visible = switch (_filter) {
      _InboxFilter.review => visible.where((item) => item.status == 'pending'),
      _InboxFilter.reminders => visible.where(
        (item) => item.status == 'snoozed',
      ),
      _InboxFilter.all => visible,
    };
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      visible = visible.where((item) {
        final bank = bankByPackage(item.packageName)?.name ?? '';
        return '${item.title} ${item.text} $bank ${_categoryFor(item)}'
            .toLowerCase()
            .contains(query);
      });
    }
    return visible.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caixa inteligente'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _clearAll();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clear',
                enabled: _items.isNotEmpty,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.done_all_rounded),
                  title: Text('Organizar tudo'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        children: [
                          _InboxOverview(
                            reviewCount: _reviewCount,
                            reminderCount: _reminderCount,
                          ),
                          const SizedBox(height: 14),
                          SearchBar(
                            controller: _searchController,
                            hintText: 'Buscar banco, categoria ou movimentação',
                            leading: const Icon(Icons.search_rounded),
                            trailing: [
                              if (_query.isNotEmpty)
                                IconButton(
                                  tooltip: 'Limpar busca',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _query = value),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<_InboxFilter>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment(
                                  value: _InboxFilter.review,
                                  icon: const Icon(Icons.inbox_rounded),
                                  label: Text('Revisar ($_reviewCount)'),
                                ),
                                ButtonSegment(
                                  value: _InboxFilter.reminders,
                                  icon: const Icon(
                                    Icons.notifications_active_outlined,
                                  ),
                                  label: Text('Depois ($_reminderCount)'),
                                ),
                                const ButtonSegment(
                                  value: _InboxFilter.all,
                                  icon: Icon(Icons.view_agenda_outlined),
                                  label: Text('Todos'),
                                ),
                              ],
                              selected: {_filter},
                              onSelectionChanged: (selection) {
                                setState(() => _filter = selection.first);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyInbox(
                        isSearching: _query.isNotEmpty,
                        showingReminders: _filter == _InboxFilter.reminders,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      sliver: SliverList.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          final suggestedIncome = item.parsedIsIncome ?? false;
                          return _SmartInboxCard(
                            item: item,
                            bank: bankByPackage(item.packageName),
                            category: _categoryFor(item),
                            amountLabel: _formatMoney(item.parsedAmount),
                            postedLabel: _formatPostedAt(item.postedAtMs),
                            reminderLabel: item.reminderAtMs == null
                                ? null
                                : _formatReminder(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      item.reminderAtMs!,
                                    ),
                                  ),
                            methodLabel: _methodLabel(item.parsedMethod),
                            suggestedIncome: suggestedIncome,
                            onReview: () =>
                                _convert(item, isIncome: suggestedIncome),
                            onOppositeType: () =>
                                _convert(item, isIncome: !suggestedIncome),
                            onRemind: () => _scheduleReminder(item),
                            onReviewNow: () => _reviewNow(item),
                            onIgnore: () => _ignore(item),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _InboxOverview extends StatelessWidget {
  const _InboxOverview({
    required this.reviewCount,
    required this.reminderCount,
  });

  final int reviewCount;
  final int reminderCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            child: const Icon(Icons.auto_awesome_rounded),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reviewCount == 0
                      ? 'Tudo organizado'
                      : '$reviewCount ${reviewCount == 1 ? 'item pede' : 'itens pedem'} sua atenção',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reminderCount == 0
                      ? 'Revise, categorize ou deixe para o melhor momento.'
                      : '$reminderCount ${reminderCount == 1 ? 'lembrete agendado' : 'lembretes agendados'}.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartInboxCard extends StatelessWidget {
  const _SmartInboxCard({
    required this.item,
    required this.bank,
    required this.category,
    required this.amountLabel,
    required this.postedLabel,
    required this.reminderLabel,
    required this.methodLabel,
    required this.suggestedIncome,
    required this.onReview,
    required this.onOppositeType,
    required this.onRemind,
    required this.onReviewNow,
    required this.onIgnore,
  });

  final PendingNotification item;
  final BankAppDefinition? bank;
  final String category;
  final String amountLabel;
  final String postedLabel;
  final String? reminderLabel;
  final String methodLabel;
  final bool suggestedIncome;
  final VoidCallback onReview;
  final VoidCallback onOppositeType;
  final VoidCallback onRemind;
  final VoidCallback onReviewNow;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scheduled = item.status == 'snoozed';
    final accent = suggestedIncome ? colors.primary : colors.tertiary;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: bank?.color ?? colors.primary,
                  foregroundColor: Colors.white,
                  child: Text(
                    bank?.initials ?? 'R\$',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bank?.name ?? 'Movimentação bancária',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '$methodLabel • $postedLabel',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Mais ações',
                  onSelected: (value) {
                    if (value == 'opposite') onOppositeType();
                    if (value == 'ignore') onIgnore();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'opposite',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          suggestedIncome
                              ? Icons.trending_down_rounded
                              : Icons.trending_up_rounded,
                        ),
                        title: Text(
                          suggestedIncome
                              ? 'Tratar como despesa'
                              : 'Tratar como receita',
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'ignore',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.visibility_off_outlined),
                        title: Text('Ignorar movimentação'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    amountLabel,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
                      const SizedBox(width: 5),
                      Text(
                        category,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item.text.trim().isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                item.text.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
            if (scheduled && reminderLabel != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      size: 19,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lembrete $reminderLabel',
                        style: TextStyle(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: scheduled ? onReviewNow : onReview,
                    icon: Icon(
                      scheduled
                          ? Icons.undo_rounded
                          : Icons.check_circle_outline_rounded,
                    ),
                    label: Text(scheduled ? 'Revisar agora' : 'Revisar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRemind,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(scheduled ? 'Alterar' : 'Lembrar'),
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

class _ReminderOption extends StatelessWidget {
  const _ReminderOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(child: Icon(icon)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({
    required this.isSearching,
    required this.showingReminders,
  });

  final bool isSearching;
  final bool showingReminders;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: Icon(
                isSearching
                    ? Icons.search_off_rounded
                    : showingReminders
                    ? Icons.notifications_none_rounded
                    : Icons.done_all_rounded,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isSearching
                  ? 'Nada encontrado'
                  : showingReminders
                  ? 'Nenhum lembrete agendado'
                  : 'Tudo organizado por aqui',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              isSearching
                  ? 'Tente buscar por outro banco, categoria ou valor.'
                  : showingReminders
                  ? 'Use “Lembrar” em uma movimentação para revisar depois.'
                  : 'Novas movimentações detectadas aparecerão automaticamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
