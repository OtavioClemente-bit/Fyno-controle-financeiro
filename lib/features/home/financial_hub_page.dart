import 'package:flutter/material.dart';

import 'accounts_cards_page.dart';
import 'categories_page.dart';
import 'fuel_extract_page.dart';
import 'investment_extract_page.dart';
import 'product_prices_page.dart';
import 'recurring_expenses_page.dart';
import 'savings_goals_page.dart';
import 'vehicles_page.dart';

class FinancialHubPage extends StatelessWidget {
  const FinancialHubPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      _HubItem(
        Icons.account_balance_wallet_rounded,
        'Contas e cartões',
        'Saldos, limites e faturas',
        () => _open(context, const AccountsCardsPage()),
      ),
      _HubItem(
        Icons.savings_rounded,
        'Metas e sonhos',
        'Guarde dinheiro para seus planos',
        () => _open(context, const SavingsGoalsPage()),
      ),
      _HubItem(
        Icons.event_repeat_rounded,
        'Mensalidades',
        'Assinaturas e contas recorrentes',
        () => _open(context, const RecurringExpensesPage()),
      ),
      _HubItem(
        Icons.trending_up_rounded,
        'Investimentos',
        'Patrimônio e evolução',
        () => _open(context, const InvestmentExtractPage()),
      ),
      _HubItem(
        Icons.directions_car_rounded,
        'Veículos',
        'Cadastro, consumo e custos',
        () => _open(context, const VehiclesPage()),
      ),
      _HubItem(
        Icons.local_gas_station_rounded,
        'Combustível',
        'Histórico de abastecimentos',
        () => _open(context, const FuelExtractPage()),
      ),
      _HubItem(
        Icons.shopping_bag_rounded,
        'Preços de produtos',
        'Compare seu histórico de compras',
        () => _open(context, const ProductPricesPage()),
      ),
      _HubItem(
        Icons.category_rounded,
        'Categorias',
        'Personalize sua organização',
        () => _open(context, const CategoriesPage()),
      ),
    ];
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Planejar'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_graph_rounded, color: cs.onPrimary),
                    const SizedBox(height: 16),
                    Text(
                      'Seu centro financeiro',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Organize o presente e planeje os próximos meses em um só lugar.',
                      style: TextStyle(
                        color: cs.onPrimary.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HubSectionTitle(
                    'Organize seu dinheiro',
                    'O essencial para planejar os próximos passos',
                  ),
                  const SizedBox(height: 10),
                  ...items.take(4).map((item) => _HubWideCard(item: item)),
                  const SizedBox(height: 16),
                  const _HubSectionTitle(
                    'Ferramentas',
                    'Recursos para acompanhar sua rotina',
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            sliver: SliverGrid.builder(
              itemCount: items.length - 4,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              itemBuilder: (_, index) => _HubCard(item: items[index + 4]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubSectionTitle extends StatelessWidget {
  const _HubSectionTitle(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class _HubWideCard extends StatelessWidget {
  const _HubWideCard({required this.item});
  final _HubItem item;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      child: ListTile(
        minTileHeight: 76,
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          child: Icon(item.icon),
        ),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(item.subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: item.onTap,
      ),
    );
  }
}

class _HubItem {
  const _HubItem(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.item});
  final _HubItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: Icon(item.icon),
              ),
              const Spacer(),
              Text(
                item.title,
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
