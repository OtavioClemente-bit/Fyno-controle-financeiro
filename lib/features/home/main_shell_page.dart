import 'package:flutter/material.dart';

import 'add_transaction_page.dart';
import 'dashboard_page.dart';
import 'financial_hub_page.dart';
import 'home_page.dart';
import 'models/tx_type.dart';
import 'profile_page.dart';

class MainShellPage extends StatefulWidget {
  const MainShellPage({super.key});

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  int _index = 0;
  int _revision = 0;

  Future<void> _openAdd() async {
    final type = await showModalBottomSheet<TxType>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Novo lançamento',
              style: Theme.of(
                sheetContext,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'O que você quer registrar agora?',
              style: TextStyle(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _AddChoice(
              icon: Icons.south_west_rounded,
              title: 'Adicionar despesa',
              subtitle: 'Compra, conta, mensalidade ou pagamento',
              onTap: () => Navigator.pop(sheetContext, TxType.expense),
            ),
            const SizedBox(height: 10),
            _AddChoice(
              icon: Icons.north_east_rounded,
              title: 'Adicionar receita',
              subtitle: 'Salário, rendimento ou outra entrada',
              onTap: () => Navigator.pop(sheetContext, TxType.income),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddTransactionPage(type: type)),
    );
    if (saved == true && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBody: false,
      body: IndexedStack(
        index: _index,
        children: [
          DashboardPage(
            key: ValueKey('dashboard-$_revision'),
            showQuickAddFab: false,
          ),
          HomePage(key: ValueKey('extract-$_revision'), showQuickAddFab: false),
          const FinancialHubPage(),
          const ProfilePage(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        tooltip: 'Adicionar lançamento',
        elevation: 3,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        notchMargin: 8,
        shape: const CircularNotchedRectangle(),
        color: cs.surfaceContainer,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Início',
              selected: _index == 0,
              onTap: () => setState(() => _index = 0),
            ),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long_rounded,
              label: 'Extrato',
              selected: _index == 1,
              onTap: () => setState(() => _index = 1),
            ),
            const SizedBox(width: 72),
            _NavItem(
              icon: Icons.grid_view_outlined,
              selectedIcon: Icons.grid_view_rounded,
              label: 'Planejar',
              selected: _index == 2,
              onTap: () => setState(() => _index = 2),
            ),
            _NavItem(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: 'Perfil',
              selected: _index == 3,
              onTap: () => setState(() => _index = 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddChoice extends StatelessWidget {
  const _AddChoice({
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
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    child: ListTile(
      minTileHeight: 76,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
