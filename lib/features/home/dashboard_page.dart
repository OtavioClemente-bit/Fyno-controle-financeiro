import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'add_transaction_page.dart';
import 'home_page.dart';
import 'vehicles_page.dart';
import 'fuel_extract_page.dart';
import 'investment_extract_page.dart';
import 'categories_page.dart';
import 'product_prices_page.dart';
import 'backup_restore_page.dart';
import 'recurring_expenses_page.dart';
import 'budgets_page.dart';
import 'accounts_cards_page.dart';
import 'financial_reminder_page.dart';
import 'budget_repository.dart';
import 'notifications/models/pages/notifications_hub_page.dart';
import 'notifications/models/pages/pending_notifications_page.dart';
import 'notifications/models/notification_bridge.dart';
import 'notifications/models/notification_inbox_service.dart';
import 'notifications/models/repositories/notification_import_repository.dart';
import 'repositories/tx_repository.dart';
import 'models/tx_type.dart';

import '../../shared/format/format_br.dart';
import '../../shared/widgets/app_settings_sheet.dart';

enum _TopMode { expense, income }

// ===== Category visual helpers (shared across widgets) =====
IconData catIcon(String category) {
  final c = category.trim().toLowerCase();
  if (c.contains('merc')) return Icons.shopping_cart_rounded;
  if (c.contains('alim')) return Icons.restaurant_rounded;
  if (c.contains('comb') || c.contains('gas')) {
    return Icons.local_gas_station_rounded;
  }
  if (c.contains('trans')) return Icons.directions_car_rounded;
  if (c.contains('saú') || c.contains('saude')) {
    return Icons.health_and_safety_rounded;
  }
  if (c.contains('farm')) return Icons.local_pharmacy_rounded;
  if (c.contains('casa') || c.contains('morad') || c.contains('alug')) {
    return Icons.home_rounded;
  }
  if (c.contains('laz') || c.contains('entre')) return Icons.movie_rounded;
  if (c.contains('edu') || c.contains('curso')) return Icons.school_rounded;
  if (c.contains('conta') ||
      c.contains('luz') ||
      c.contains('água') ||
      c.contains('agua') ||
      c.contains('internet')) {
    return Icons.receipt_long_rounded;
  }
  if (c.contains('sal') || c.contains('pag')) {
    return Icons.account_balance_wallet_rounded;
  }
  return Icons.category_rounded;
}

Color catTint(BuildContext context, String category) {
  final cs = Theme.of(context).colorScheme;
  final c = category.trim().toLowerCase();
  if (c.contains('comb') || c.contains('gas')) return cs.tertiary;
  if (c.contains('merc')) return cs.primary;
  if (c.contains('alim')) return cs.secondary;
  if (c.contains('trans')) return cs.primaryContainer;
  if (c.contains('saú') || c.contains('saude') || c.contains('farm')) {
    return cs.error;
  }
  if (c.contains('casa') || c.contains('morad') || c.contains('alug')) {
    return cs.secondaryContainer;
  }
  if (c.contains('laz') || c.contains('entre')) return cs.tertiaryContainer;
  if (c.contains('edu') || c.contains('curso')) return cs.primary;
  if (c.contains('sal') || c.contains('pag')) return cs.primary;
  return cs.outline;
}
// ==========================================================

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.showQuickAddFab = true});

  final bool showQuickAddFab;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  final TxRepository _repo = TxRepository();
  final NotificationInboxService _notificationInboxService =
      NotificationInboxService();
  final NotificationImportRepository _notificationImportRepository =
      NotificationImportRepository();
  Timer? _notificationSyncTimer;
  bool _notificationSyncInProgress = false;

  bool _loading = true;

  double _saldo = 0;
  double _incomeMonth = 0;
  double _expenseMonth = 0;
  double _creditPurchases = 0;
  double _creditPayments = 0;
  int _totalCount = 0;
  int _pendingNotificationCount = 0;
  int _scheduledReminderCount = 0;
  int _budgetAlertCount = 0;
  bool _hasExceededBudget = false;

  // Mês de referência exibido no dashboard
  DateTime _refMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // Top categorias (despesas/receitas)
  List<MapEntry<String, double>> _topExpenseCategories = [];
  List<MapEntry<String, double>> _topIncomeCategories = [];
  _TopMode _topMode = _TopMode.expense;

  // UX
  bool _hideValues = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _notificationSyncTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshNotificationCount(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openReminderFromSystem(),
    );
  }

  @override
  void dispose() {
    _notificationSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _openReminderFromSystem();
    }
  }

  Future<void> _openReminderFromSystem() async {
    final reminderId = await NotificationBridge.instance
        .consumeLaunchedReminder();
    if (reminderId == null || !mounted) return;
    if (reminderId == FinancialReminderPage.notificationId) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PendingNotificationsPage()),
    );
    if (mounted) await _load();
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  Future<void> _refreshNotificationCount() async {
    if (_notificationSyncInProgress) return;
    _notificationSyncInProgress = true;
    try {
      final count = await _notificationInboxService.sync();
      final reminders = await _notificationImportRepository
          .countScheduledReminders();
      if (mounted &&
          (count != _pendingNotificationCount ||
              reminders != _scheduledReminderCount)) {
        setState(() {
          _pendingNotificationCount = count;
          _scheduledReminderCount = reminders;
        });
      }
    } catch (_) {
      // A captura nativa continua ativa; uma próxima sincronização tenta de novo.
    } finally {
      _notificationSyncInProgress = false;
    }
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _monthEndExclusive(DateTime d) => DateTime(d.year, d.month + 1, 1);

  String _monthNamePt(int m) {
    const meses = [
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
    ];
    return meses[(m - 1).clamp(0, 11)];
  }

  String _money(double v) => FormatBR.money(v);

  Future<void> _load() async {
    setState(() => _loading = true);

    final all = await _repo.getAll();
    var pendingNotificationCount = _pendingNotificationCount;
    var scheduledReminderCount = _scheduledReminderCount;
    var budgetAlertCount = 0;
    var hasExceededBudget = false;
    try {
      pendingNotificationCount = await _notificationInboxService.sync();
      scheduledReminderCount = await _notificationImportRepository
          .countScheduledReminders();
    } catch (_) {}
    try {
      final budgets = await BudgetRepository().getProgress(_refMonth);
      final alerts = budgets.where(
        (item) => item.ratio >= item.budget.warningPercent / 100,
      );
      budgetAlertCount = alerts.length;
      hasExceededBudget = alerts.any((item) => item.exceeded);
    } catch (_) {}

    final start = _monthStart(_refMonth);
    final endEx = _monthEndExclusive(_refMonth);

    double inMonth = 0;
    double outMonth = 0;

    // Top categorias do mês (despesa/receita)
    final Map<String, double> mapExpense = {};
    final Map<String, double> mapIncome = {};

    for (final tx in all) {
      final dt = tx.date;
      final inRange = !dt.isBefore(start) && dt.isBefore(endEx);
      if (!inRange) continue;

      if (tx.isIncome) {
        inMonth += tx.amount;
        mapIncome[tx.category] = (mapIncome[tx.category] ?? 0) + tx.amount;
      } else if (tx.countsAsExpense) {
        outMonth += tx.amount;
        mapExpense[tx.category] = (mapExpense[tx.category] ?? 0) + tx.amount;
      }
    }

    // saldo geral (todas)
    double saldo = 0;
    double creditPurchases = 0;
    double creditPayments = 0;
    for (final tx in all) {
      if (tx.isCreditPurchase) creditPurchases += tx.amount;
      if (tx.isCreditCardBillPayment) creditPayments += tx.amount;
      if (tx.isCreditCardBillPayment) continue;
      saldo += tx.isIncome ? tx.amount : -tx.amount;
    }

    final topExpense = mapExpense.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topIncome = mapIncome.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    setState(() {
      _saldo = saldo;
      _incomeMonth = inMonth;
      _expenseMonth = outMonth;
      _creditPurchases = creditPurchases;
      _creditPayments = creditPayments;
      _totalCount = all.length;
      _pendingNotificationCount = pendingNotificationCount;
      _scheduledReminderCount = scheduledReminderCount;
      _budgetAlertCount = budgetAlertCount;
      _hasExceededBudget = hasExceededBudget;
      _topExpenseCategories = topExpense.take(5).toList();
      _topIncomeCategories = topIncome.take(5).toList();
      _loading = false;
    });
  }

  Future<void> _openAdd(TxType type) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddTransactionPage(type: type)),
    );
    if (saved == true) {
      if (!mounted) return;
      await _load();
    }
  }

  void _openHome() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  void _openVehicles() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VehiclesPage()),
    );
  }

  void _openFuelExtract() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FuelExtractPage()),
    );
  }

  void _openInvestExtract() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InvestmentExtractPage()),
    );
  }

  void _openCategories() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriesPage()),
    ).then((_) => _load());
  }

  void _openProductPrices() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductPricesPage()),
    ).then((_) => _load());
  }

  void _openRecurringExpenses() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecurringExpensesPage()),
    ).then((_) => _load());
  }

  void _openBudgets() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BudgetsPage()),
    ).then((_) => _load());
  }

  void _openAccountsCards() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountsCardsPage()),
    ).then((_) => _load());
  }

  Future<void> _openNotificationsHub() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsHubPage()),
    );
    if (mounted) await _load();
  }

  Future<void> _openBackupSheet() async {
    final restored = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BackupRestorePage()),
    );
    if (restored == true && mounted) await _load();
  }

  void _openSettings() {
    AppSettingsSheet.show(
      context,
      onOpenPermissions: () {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showPermissionsSheet(),
        );
      },
      onOpenBackup: () {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) => _openBackupSheet());
      },
    );
  }

  void _showPermissionsSheet() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final cs = theme.colorScheme;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            20 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Permissões', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Ative somente os acessos usados pelos recursos abaixo.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              const _PermissionInfo(
                icon: Icons.photo_camera_rounded,
                title: 'Câmera',
                description: 'Usada para ler o QR Code de cupons.',
              ),
              const SizedBox(height: 10),
              const _PermissionInfo(
                icon: Icons.mark_email_read_rounded,
                title: 'Acesso às notificações',
                description:
                    'Lê apenas transações dos bancos escolhidos, com seu '
                    'consentimento, para sugerir lançamentos.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _openNotificationsHub(),
                  );
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Configurar transações detectadas'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openAppSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Abrir configurações do aplicativo'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _prevMonth() {
    setState(() {
      _refMonth = DateTime(_refMonth.year, _refMonth.month - 1, 1);
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month, 1);
    if (_refMonth.isAtSameMomentAs(current)) return;
    setState(() {
      _refMonth = DateTime(_refMonth.year, _refMonth.month + 1, 1);
    });
    _load();
  }

  void _toggleHideValues() {
    setState(() => _hideValues = !_hideValues);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(_hideValues ? 'Valores ocultos' : 'Valores exibidos'),
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  Future<void> _openQuickAdd() async {
    final choice = await showModalBottomSheet<TxType>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Novo lançamento',
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                _QuickAddTile(
                  icon: Icons.trending_up_rounded,
                  title: 'Adicionar receita',
                  subtitle: 'Entrada de dinheiro',
                  onTap: () => Navigator.pop(ctx, TxType.income),
                ),
                const SizedBox(height: 12),
                _QuickAddTile(
                  icon: Icons.trending_down_rounded,
                  title: 'Adicionar despesa',
                  subtitle: 'Saída de dinheiro',
                  onTap: () => Navigator.pop(ctx, TxType.expense),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (choice != null) {
      await _openAdd(choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = '${_monthNamePt(_refMonth.month)} ${_refMonth.year}';

    final isPositive = _saldo >= 0;
    final saldoAbs = _money(_saldo.abs());

    final cs = Theme.of(context).colorScheme;
    final bg = cs.surface;

    final useCompactFab =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.25;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: !widget.showQuickAddFab
          ? null
          : useCompactFab
          ? FloatingActionButton(
              onPressed: _openQuickAdd,
              tooltip: 'Novo lançamento',
              child: const Icon(Icons.add_rounded),
            )
          : FloatingActionButton.extended(
              onPressed: _openQuickAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    surfaceTintColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                    expandedHeight: 260,
                    automaticallyImplyLeading: false,
                    titleSpacing: 16,
                    title: Row(
                      children: [
                        const _FynoLogo(size: 30, radius: 10),
                        const SizedBox(width: 10),
                        const Text(
                          'Fyno',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: .2,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        tooltip: _hideValues
                            ? 'Mostrar valores'
                            : 'Ocultar valores',
                        icon: Icon(
                          _hideValues
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                        onPressed: _toggleHideValues,
                      ),
                      IconButton(
                        tooltip: 'Notificações',
                        icon: Badge(
                          isLabelVisible: _pendingNotificationCount > 0,
                          label: Text('$_pendingNotificationCount'),
                          child: const Icon(Icons.notifications_rounded),
                        ),
                        onPressed: _openNotificationsHub,
                      ),
                      IconButton(
                        tooltip: 'Aparência e ajustes',
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: _openSettings,
                      ),
                      const SizedBox(width: 8),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: _PremiumHeader(
                        title: 'Finanças',
                        subtitle: 'Resumo do mês',
                        monthLabel: monthLabel,
                        onPrevMonth: _prevMonth,
                        onNextMonth: _nextMonth,
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        children: [
                          _ProBalanceCard(
                            monthLabel: monthLabel,
                            isPositive: isPositive,
                            value: _hideValues
                                ? '•••••'
                                : (isPositive ? '+$saldoAbs' : '-$saldoAbs'),
                            subtitle: _hideValues
                                ? 'Saldo total'
                                : (isPositive
                                      ? 'Você está no positivo'
                                      : 'Atenção: saldo negativo'),
                          ),

                          if (_pendingNotificationCount > 0 ||
                              _scheduledReminderCount > 0) ...[
                            const SizedBox(height: 14),
                            _DetectedTransactionsCard(
                              count: _pendingNotificationCount,
                              reminderCount: _scheduledReminderCount,
                              onTap: _openNotificationsHub,
                            ),
                          ],

                          const SizedBox(height: 14),

                          _MetricsRow(
                            hideValues: _hideValues,
                            incomeMonth: _incomeMonth,
                            expenseMonth: _expenseMonth,
                            money: _money,
                          ),

                          if (_creditPurchases > 0 || _creditPayments > 0) ...[
                            const SizedBox(height: 14),
                            _CreditCardBalanceCard(
                              purchases: _creditPurchases,
                              payments: _creditPayments,
                              hideValues: _hideValues,
                              money: _money,
                            ),
                          ],

                          if (_budgetAlertCount > 0) ...[
                            const SizedBox(height: 14),
                            _BudgetAlertCard(
                              count: _budgetAlertCount,
                              exceeded: _hasExceededBudget,
                              onTap: _openBudgets,
                            ),
                          ],

                          const SizedBox(height: 14),

                          // No shell principal, essas ferramentas ficam reunidas
                          // na aba Planejar para manter o início mais limpo.
                          if (widget.showQuickAddFab)
                            _ActionsRow(
                              onHome: _openHome,
                              onVehicles: _openVehicles,
                              onFuelExtract: _openFuelExtract,
                              onInvestExtract: _openInvestExtract,
                              onCategories: _openCategories,
                              onProducts: _openProductPrices,
                              onRecurringExpenses: _openRecurringExpenses,
                              onBudgets: _openBudgets,
                              onAccountsCards: _openAccountsCards,
                            ),

                          const SizedBox(height: 18),

                          _TopOfMonthSection(
                            mode: _topMode,
                            onModeChanged: (m) => setState(() => _topMode = m),
                            expenseEntries: _topExpenseCategories,
                            incomeEntries: _topIncomeCategories,
                            totalExpenseMonth: _expenseMonth,
                            totalIncomeMonth: _incomeMonth,
                            money: _money,
                            hideValues: _hideValues,
                          ),

                          const SizedBox(height: 16),

                          _InsightsCard(
                            totalCount: _totalCount,
                            monthLabel: monthLabel,
                            incomeMonth: _incomeMonth,
                            expenseMonth: _expenseMonth,
                            hideValues: _hideValues,
                            money: _money,
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/* -----------------------------
 *  UI — Premium Widgets
 * ----------------------------- */

class _CreditCardBalanceCard extends StatelessWidget {
  const _CreditCardBalanceCard({
    required this.purchases,
    required this.payments,
    required this.hideValues,
    required this.money,
  });

  final double purchases;
  final double payments;
  final bool hideValues;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outstanding = (purchases - payments)
        .clamp(0, double.infinity)
        .toDouble();
    String value(double amount) => hideValues ? '•••••' : money(amount);

    return Card(
      elevation: 0,
      color: cs.tertiaryContainer.withValues(alpha: .55),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card_rounded, color: cs.onTertiaryContainer),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Cartão de crédito',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  value(outstanding),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Em aberto • compras ${value(purchases)} − pagamentos ${value(payments)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectedTransactionsCard extends StatelessWidget {
  const _DetectedTransactionsCard({
    required this.count,
    required this.reminderCount,
    required this.onTap,
  });

  final int count;
  final int reminderCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.secondary,
                foregroundColor: colors.onSecondary,
                child: const Icon(Icons.receipt_long_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0
                          ? '$reminderCount ${reminderCount == 1 ? 'lembrete agendado' : 'lembretes agendados'}'
                          : '$count ${count == 1 ? 'transação para revisar' : 'transações para revisar'}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reminderCount == 0
                          ? 'Revise antes de adicionar ao seu controle.'
                          : '$reminderCount ${reminderCount == 1 ? 'item está' : 'itens estão'} separado para depois.',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _FynoLogo extends StatelessWidget {
  final double size;
  final double radius;

  const _FynoLogo({this.size = 36, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .03),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: dark ? .12 : .08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.primary.withValues(alpha: .16)),
      ),
      child: Image.asset(
        dark
            ? 'assets/brand/fyno_mark_compact_on_dark.png'
            : 'assets/brand/fyno_mark_compact.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.auto_graph_rounded, size: size * .55, color: cs.primary),
      ),
    );
  }
}

class _PremiumHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  final String monthLabel;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _PremiumHeader({
    required this.title,
    required this.subtitle,
    required this.monthLabel,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: .18),
            cs.secondary.withValues(alpha: .10),
            cs.tertiary.withValues(alpha: .14),
          ],
        ),
      ),
      child: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          // Empurra o conteúdo para baixo do AppBar (evita sobreposição dos botões)
          padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 28, 16, 12),
          child: Stack(
            children: [
              // Marca d'água (logo) — deixa o topo com identidade sem poluir
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Opacity(
                      opacity: .10,
                      child: const _FynoLogo(size: 170, radius: 48),
                    ),
                  ),
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Month switcher (centered label, arrows never overlap)
                  _MonthSwitcher(
                    monthLabel: monthLabel,
                    onPrev: onPrevMonth,
                    onNext: onNextMonth,
                  ),

                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: _ChipBadge(
                      icon: Icons.auto_graph_rounded,
                      label: 'Visão geral',
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

class _MonthSwitcher extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthSwitcher({
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        _MonthNavButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Mês anterior',
          onTap: onPrev,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .55),
              ),
            ),
            child: Center(
              child: Text(
                monthLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.1,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _MonthNavButton(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Próximo mês',
          onTap: onNext,
        ),
      ],
    );
  }
}

class _ProBalanceCard extends StatelessWidget {
  final String monthLabel;
  final bool isPositive;
  final String value;
  final String subtitle;

  const _ProBalanceCard({
    required this.monthLabel,
    required this.isPositive,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark ? const Color(0xFF0D6B50) : cs.primary,
            isDark ? const Color(0xFF74453F) : cs.tertiary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 26,
            offset: const Offset(0, 14),
            color: cs.primary.withValues(alpha: .20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Saldo total',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: .95),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              );
              final month = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .22),
                  ),
                ),
                child: Text(
                  monthLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .92),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              if (constraints.maxWidth < 330 || textScale > 1.25) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 10), month],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 10),
                  month,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: SizedBox(
              key: ValueKey(value),
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.6,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                isPositive
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: Colors.white.withValues(alpha: .92),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .88),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  final bool hideValues;
  final double incomeMonth;
  final double expenseMonth;
  final String Function(double) money;

  const _MetricsRow({
    required this.hideValues,
    required this.incomeMonth,
    required this.expenseMonth,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final saved = (incomeMonth - expenseMonth);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 600 || textScale > 1.25;

        if (compact) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.trending_up_rounded,
                      title: 'Receitas',
                      value: hideValues ? '•••••' : money(incomeMonth),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.trending_down_rounded,
                      title: 'Despesas',
                      value: hideValues ? '•••••' : money(expenseMonth),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _MetricCard(
                  icon: Icons.savings_rounded,
                  title: 'Economia',
                  value: hideValues ? '•••••' : money(saved),
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.trending_up_rounded,
                title: 'Receitas',
                value: hideValues ? '•••••' : money(incomeMonth),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.trending_down_rounded,
                title: 'Despesas',
                value: hideValues ? '•••••' : money(expenseMonth),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.savings_rounded,
                title: 'Economia',
                value: hideValues ? '•••••' : money(saved),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: SizedBox(
              key: ValueKey(value),
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetAlertCard extends StatelessWidget {
  const _BudgetAlertCard({
    required this.count,
    required this.exceeded,
    required this.onTap,
  });

  final int count;
  final bool exceeded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = exceeded ? cs.error : Colors.orange.shade800;
    return Material(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .16),
                child: Icon(
                  exceeded ? Icons.warning_amber_rounded : Icons.speed_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exceeded
                          ? 'Orçamento ultrapassado'
                          : 'Orçamento perto do limite',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '$count ${count == 1 ? 'categoria precisa' : 'categorias precisam'} de atenção',
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

class _ActionsRow extends StatelessWidget {
  final VoidCallback onHome;
  final VoidCallback onVehicles;
  final VoidCallback onFuelExtract;
  final VoidCallback onInvestExtract;
  final VoidCallback onCategories;
  final VoidCallback onProducts;
  final VoidCallback onRecurringExpenses;
  final VoidCallback onBudgets;
  final VoidCallback onAccountsCards;

  const _ActionsRow({
    required this.onHome,
    required this.onVehicles,
    required this.onFuelExtract,
    required this.onInvestExtract,
    required this.onCategories,
    required this.onProducts,
    required this.onRecurringExpenses,
    required this.onBudgets,
    required this.onAccountsCards,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionGroup(
          eyebrow: 'PLANEJAMENTO',
          title: 'Organize o próximo passo',
          items: [
            _ActionItem(
              Icons.account_balance_wallet_rounded,
              'Contas e cartões',
              'Faturas, limites e saldos',
              onAccountsCards,
            ),
            _ActionItem(
              Icons.donut_large_rounded,
              'Orçamentos',
              'Limites e alertas mensais',
              onBudgets,
            ),
            _ActionItem(
              Icons.subscriptions_rounded,
              'Mensalidades',
              'Assinaturas e vencimentos',
              onRecurringExpenses,
            ),
            _ActionItem(
              Icons.insights_rounded,
              'Investimentos',
              'Acompanhe sua evolução',
              onInvestExtract,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ActionGroup(
          eyebrow: 'GESTÃO',
          title: 'Seus registros',
          items: [
            _ActionItem(
              Icons.list_alt_rounded,
              'Extrato',
              'Todas as movimentações',
              onHome,
            ),
            _ActionItem(
              Icons.local_gas_station_rounded,
              'Combustível',
              'Gastos e abastecimentos',
              onFuelExtract,
            ),
            _ActionItem(
              Icons.directions_car_rounded,
              'Veículos',
              'Cadastro e consumo',
              onVehicles,
            ),
            _ActionItem(
              Icons.shopping_bag_rounded,
              'Produtos',
              'Histórico de preços',
              onProducts,
            ),
            _ActionItem(
              Icons.category_rounded,
              'Categorias',
              'Personalize a organização',
              onCategories,
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionItem {
  const _ActionItem(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({
    required this.eyebrow,
    required this.title,
    required this.items,
  });

  final String eyebrow;
  final String title;
  final List<_ActionItem> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 66,
                color: cs.outlineVariant.withValues(alpha: .45),
              ),
            _ActionRow(item: items[index]),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.item});
  final _ActionItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, size: 21, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _TopOfMonthSection extends StatelessWidget {
  final _TopMode mode;
  final ValueChanged<_TopMode> onModeChanged;

  final List<MapEntry<String, double>> expenseEntries;
  final List<MapEntry<String, double>> incomeEntries;

  final double totalExpenseMonth;
  final double totalIncomeMonth;

  final String Function(double) money;
  final bool hideValues;

  const _TopOfMonthSection({
    required this.mode,
    required this.onModeChanged,
    required this.expenseEntries,
    required this.incomeEntries,
    required this.totalExpenseMonth,
    required this.totalIncomeMonth,
    required this.money,
    required this.hideValues,
  });

  @override
  Widget build(BuildContext context) {
    final entries = mode == _TopMode.expense ? expenseEntries : incomeEntries;
    final total = mode == _TopMode.expense
        ? totalExpenseMonth
        : totalIncomeMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Top do mês',
          subtitle: mode == _TopMode.expense
              ? 'Onde você mais gastou'
              : 'De onde mais entrou',
          trailing: _TopModeToggle(mode: mode, onChanged: onModeChanged),
        ),
        const SizedBox(height: 10),
        entries.isEmpty
            ? const _EmptyTopCategoriesCard()
            : _TopCategoriesCard(
                entries: entries,
                total: total,
                money: money,
                hideValues: hideValues,
              ),
      ],
    );
  }
}

class _TopModeToggle extends StatelessWidget {
  final _TopMode mode;
  final ValueChanged<_TopMode> onChanged;

  const _TopModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ToggleChip(
          selected: mode == _TopMode.expense,
          label: 'Despesas',
          icon: Icons.trending_down_rounded,
          onTap: () => onChanged(_TopMode.expense),
        ),
        _ToggleChip(
          selected: mode == _TopMode.income,
          label: 'Receitas',
          icon: Icons.trending_up_rounded,
          onTap: () => onChanged(_TopMode.income),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: .14)
              : cs.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: .55)
                : cs.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopCategoriesCard extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  final double total;
  final String Function(double) money;
  final bool hideValues;

  const _TopCategoriesCard({
    required this.entries,
    required this.total,
    required this.money,
    required this.hideValues,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        children: [
          for (final e in entries) ...[
            _CategoryProgressRow(
              category: e.key,
              value: e.value,
              total: total <= 0 ? e.value : total,
              money: money,
              hideValues: hideValues,
            ),
            if (e != entries.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CategoryProgressRow extends StatelessWidget {
  final String category;
  final double value;
  final double total;
  final String Function(double) money;
  final bool hideValues;

  const _CategoryProgressRow({
    required this.category,
    required this.value,
    required this.total,
    required this.money,
    required this.hideValues,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0.0 : (value / total).clamp(0.0, 1.0);

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: catTint(context, category).withValues(alpha: .14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            catIcon(category),
            color: catTint(context, category),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hideValues ? '•••••' : money(value),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: cs.outlineVariant.withValues(alpha: .35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyTopCategoriesCard extends StatelessWidget {
  const _EmptyTopCategoriesCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sem dados suficientes neste mês para montar o Top.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  final int totalCount;
  final String monthLabel;
  final double incomeMonth;
  final double expenseMonth;
  final bool hideValues;
  final String Function(double) money;

  const _InsightsCard({
    required this.totalCount,
    required this.monthLabel,
    required this.incomeMonth,
    required this.expenseMonth,
    required this.hideValues,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final net = incomeMonth - expenseMonth;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Insights',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: .70),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: .55),
                  ),
                ),
                child: Text(
                  monthLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final oneColumn = constraints.maxWidth < 340 || textScale > 1.3;
              final itemWidth = oneColumn
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _MiniStat(
                      icon: Icons.receipt_long_rounded,
                      title: 'Total de lançamentos',
                      value: '$totalCount',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _MiniStat(
                      icon: Icons.account_balance_rounded,
                      title: 'Resultado do mês',
                      value: hideValues ? '•••••' : money(net),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _MiniStat(
                      icon: Icons.trending_up_rounded,
                      title: 'Receita do mês',
                      value: hideValues ? '•••••' : money(incomeMonth),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _MiniStat(
                      icon: Icons.trending_down_rounded,
                      title: 'Despesa do mês',
                      value: hideValues ? '•••••' : money(expenseMonth),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _MiniStat({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 430 || textScale > 1.2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), trailing],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            trailing,
          ],
        );
      },
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MonthNavButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: .55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: cs.onSurface, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ChipBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ChipBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    // Reaproveita o estilo do _Pill para manter o visual consistente
    // e evita warnings de elemento não utilizado.
    return _Pill(icon: icon, label: label, onTap: () {});
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Pill({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAddTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(16),
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
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionInfo extends StatelessWidget {
  const _PermissionInfo({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
