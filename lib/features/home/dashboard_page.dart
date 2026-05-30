import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

import 'add_transaction_page.dart';
import 'home_page.dart';
import 'vehicles_page.dart';
import 'fuel_extract_page.dart';
import 'investment_extract_page.dart';
import 'categories_page.dart';
import 'product_prices_page.dart';
import 'notifications/models/pages/notifications_hub_page.dart';
import 'repositories/tx_repository.dart';
import 'models/tx_type.dart';

import '../../shared/format/format_br.dart';

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
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TxRepository _repo = TxRepository();

  bool _loading = true;

  double _saldo = 0;
  double _incomeMonth = 0;
  double _expenseMonth = 0;
  int _totalCount = 0;

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
    _load();

    // Permissões necessárias para QR Code (câmera) e notificações (Android 13+).
    // OBS: "Acesso às notificações" (Notification Listener) é uma permissão ESPECIAL
    // que o usuário ativa manualmente nas configurações do Android.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureRuntimePermissions(),
    );
  }

  Future<void> _ensureRuntimePermissions() async {
    // 1) Câmera (QR Code / cupom)
    try {
      final camStatus = await Permission.camera.status;
      if (!camStatus.isGranted) {
        await Permission.camera.request();
      }
    } catch (_) {}

    // 2) Notificações (Android 13+) - permite o app EXIBIR notificações.
    // Não é o mesmo que "Acesso às notificações" (Notification Listener).
    try {
      if (Platform.isAndroid) {
        final notifStatus = await Permission.notification.status;
        if (!notifStatus.isGranted) {
          await Permission.notification.request();
        }
      }
    } catch (_) {}

    // 3) Acesso às notificações (Notification Listener) - o Android NÃO permite pedir via pop-up.
    // Você precisa abrir a tela de configurações para o usuário ativar manualmente.
    // Se você quiser forçar isso já no começo, descomenta a linha abaixo:
    // await _openNotificationListenerSettings();
  }

  Future<void> _openNotificationListenerSettings() async {
    if (!Platform.isAndroid) return;

    final intent = AndroidIntent(
      action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
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
      } else {
        outMonth += tx.amount;
        mapExpense[tx.category] = (mapExpense[tx.category] ?? 0) + tx.amount;
      }
    }

    // saldo geral (todas)
    double saldo = 0;
    for (final tx in all) {
      saldo += (tx.isIncome) ? tx.amount : -tx.amount;
    }

    final topExpense = mapExpense.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topIncome = mapIncome.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    setState(() {
      _saldo = saldo;
      _incomeMonth = inMonth;
      _expenseMonth = outMonth;
      _totalCount = all.length;
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

  void _openNotificationsHub() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsHubPage()),
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
      isScrollControlled: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
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

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton.extended(
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
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Permissões',
                        icon: const Icon(Icons.admin_panel_settings_rounded),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            builder: (_) => SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Permissões',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      '• Câmera: necessário para ler QR Code.'
                                      '• Notificações (Android 13+): permite o app exibir notificações.'
                                      '• "Acesso às notificações" (Listener): necessário para o app LER notificações — você ativa manualmente nas configurações.',
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed:
                                          _openNotificationListenerSettings,
                                      icon: const Icon(
                                        Icons.notifications_active_outlined,
                                      ),
                                      label: const Text(
                                        'Ativar "Acesso às notificações"',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: _openAppSettings,
                                      icon: const Icon(Icons.settings_outlined),
                                      label: const Text(
                                        'Abrir configurações do app',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Fechar'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Notificações',
                        icon: const Icon(Icons.notifications_rounded),
                        onPressed: _openNotificationsHub,
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

                          const SizedBox(height: 14),

                          _MetricsRow(
                            hideValues: _hideValues,
                            incomeMonth: _incomeMonth,
                            expenseMonth: _expenseMonth,
                            money: _money,
                          ),

                          const SizedBox(height: 14),

                          _ActionsRow(
                            onHome: _openHome,
                            onVehicles: _openVehicles,
                            onFuelExtract: _openFuelExtract,
                            onInvestExtract: _openInvestExtract,
                            onCategories: _openCategories,
                            onProducts: _openProductPrices,
                          ),

                          const SizedBox(height: 18),

                          TopOfMonthSection(
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

class _FynoLogo extends StatelessWidget {
  final double size;
  final double radius;

  const _FynoLogo({this.size = 36, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/icons/fyno_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: .35)),
          ),
          child: Icon(Icons.send_rounded, size: size * .55, color: cs.primary),
        ),
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
          padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 14, 16, 12),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: .95),
            cs.tertiary.withValues(alpha: .90),
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
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Saldo total',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .95),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
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
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Text(
              value,
              key: ValueKey(value),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -.6,
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
        final compact = constraints.maxWidth < 360;

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
              _MetricCard(
                icon: Icons.savings_rounded,
                title: 'Economia',
                value: hideValues ? '•••••' : money(saved),
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
            child: Text(
              value,
              key: ValueKey(value),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -.2,
              ),
            ),
          ),
        ],
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

  const _ActionsRow({
    required this.onHome,
    required this.onVehicles,
    required this.onFuelExtract,
    required this.onInvestExtract,
    required this.onCategories,
    required this.onProducts,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _ActionTile(
        icon: Icons.list_alt_rounded,
        title: 'Extrato',
        subtitle: 'Lançamentos',
        onTap: onHome,
      ),
      _ActionTile(
        icon: Icons.directions_car_rounded,
        title: 'Veículos',
        subtitle: 'Cadastro',
        onTap: onVehicles,
      ),
      _ActionTile(
        icon: Icons.local_gas_station_rounded,
        title: 'Combustível',
        subtitle: 'Extrato',
        onTap: onFuelExtract,
      ),
      _ActionTile(
        icon: Icons.insights_rounded,
        title: 'Investimentos',
        subtitle: 'Extrato',
        onTap: onInvestExtract,
      ),
      _ActionTile(
        icon: Icons.category_rounded,
        title: 'Categorias',
        subtitle: 'Gerenciar',
        onTap: onCategories,
      ),
      _ActionTile(
        icon: Icons.shopping_bag_rounded,
        title: 'Produtos',
        subtitle: 'Preços',
        onTap: onProducts,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 520 ? 3 : 2;
        final ratio = w >= 520 ? 2.20 : 2.30;

        return GridView.count(
          crossAxisCount: cols,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: ratio,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: tiles,
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: .65),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TopOfMonthSection extends StatelessWidget {
  final _TopMode mode;
  final ValueChanged<_TopMode> onModeChanged;

  final List<MapEntry<String, double>> expenseEntries;
  final List<MapEntry<String, double>> incomeEntries;

  final double totalExpenseMonth;
  final double totalIncomeMonth;

  final String Function(double) money;
  final bool hideValues;

  const TopOfMonthSection({
    super.key,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleChip(
          selected: mode == _TopMode.expense,
          label: 'Despesas',
          icon: Icons.trending_down_rounded,
          onTap: () => onChanged(_TopMode.expense),
        ),
        const SizedBox(width: 8),
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
              final itemWidth = (constraints.maxWidth - 10) / 2;
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
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
          ),
        ),
        trailing,
      ],
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
