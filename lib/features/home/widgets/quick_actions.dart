import 'package:flutter/material.dart';
import '../../../app/theme/color_schemes.dart';

class QuickActions extends StatelessWidget {
  final VoidCallback onAddIncome;
  final VoidCallback onAddExpense;
  final VoidCallback onCategories;

  const QuickActions({
    super.key,
    required this.onAddIncome,
    required this.onAddExpense,
    required this.onCategories,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _action(
            icon: Icons.add_circle_outline,
            title: 'Receita',
            subtitle: 'Adicionar',
            onTap: onAddIncome,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _action(
            icon: Icons.remove_circle_outline,
            title: 'Despesa',
            subtitle: 'Adicionar',
            onTap: onAddExpense,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _action(
            icon: Icons.category_outlined,
            title: 'Categorias',
            subtitle: 'Gerenciar',
            onTap: onCategories,
          ),
        ),
      ],
    );
  }

  Widget _action({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
