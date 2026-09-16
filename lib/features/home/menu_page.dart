import 'package:flutter/material.dart';

import 'add_transaction_page.dart';
import 'home_page.dart';
import 'vehicles_page.dart';
import 'models/tx_type.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  Future<void> _openAdd(TxType type) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddTransactionPage(type: type)),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transação salva no SQLite ✅')),
      );
    }
  }

  void _openExtract() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Controle Financeiro')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const SizedBox(height: 8),
          const Text(
            'O que você quer fazer agora?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          _BigActionButton(
            icon: Icons.add_circle,
            title: 'Adicionar Receita',
            subtitle: 'Registrar entrada de dinheiro',
            onTap: () => _openAdd(TxType.income),
          ),
          const SizedBox(height: 12),

          _BigActionButton(
            icon: Icons.remove_circle,
            title: 'Adicionar Despesa',
            subtitle: 'Registrar saída de dinheiro',
            onTap: () => _openAdd(TxType.expense),
          ),
          const SizedBox(height: 12),

          _BigActionButton(
            icon: Icons.list_alt,
            title: 'Ver Transações',
            subtitle: 'Abrir extrato (SQLite)',
            onTap: _openExtract,
          ),

          const SizedBox(height: 12),

          _BigActionButton(
            icon: Icons.directions_car_rounded,
            title: 'Veículos',
            subtitle: 'Abastecimentos e consumo (km/L)',
            onTap: _openVehicles,
          ),
        ],
      ),
    );
  }
}

class _BigActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BigActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 22, child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
