import 'package:flutter/material.dart';
import '../../../app/theme/color_schemes.dart';

class BalanceCard extends StatelessWidget {
  final double balance;
  final double income;
  final double expense;

  const BalanceCard({
    super.key,
    required this.balance,
    required this.income,
    required this.expense,
  });

  String brl(double v) {
    // UI simples (depois a gente coloca intl certinho)
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return 'R\$ $s';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo do mês', style: t.bodySmall),
            const SizedBox(height: 6),
            Text(brl(balance), style: t.titleLarge),
            const SizedBox(height: 14),
            Row(
              children: [
                _pill(
                  label: 'Receitas',
                  value: brl(income),
                  color: AppColors.success,
                ),
                const SizedBox(width: 10),
                _pill(
                  label: 'Despesas',
                  value: brl(expense),
                  color: AppColors.danger,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
