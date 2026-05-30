import 'package:flutter/material.dart';

import 'models/vehicle.dart';
import 'models/fuel_log.dart';
import 'repositories/fuel_log_repository.dart';
import 'add_fuel_log_page.dart';

class FuelLogsPage extends StatefulWidget {
  final Vehicle vehicle;
  const FuelLogsPage({super.key, required this.vehicle});

  @override
  State<FuelLogsPage> createState() => _FuelLogsPageState();
}

class _FuelLogsPageState extends State<FuelLogsPage> {
  final FuelLogRepository _repo = FuelLogRepository();

  Future<List<FuelLog>> _load() => _repo.getByVehicle(widget.vehicle.id!);

  Future<void> _openAdd() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddFuelLogPage(vehicle: widget.vehicle),
      ),
    );

    if (ok == true && mounted) setState(() {});
  }

  // ✅ pega o millis de forma compatível mesmo que o model não tenha "dateMs"
  int _getDateMs(FuelLog log) {
    // Se seu FuelLog tiver dateMs, fica perfeito:
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    try {
      final dyn = log as dynamic;

      // nomes comuns
      final candidates = <dynamic>[
        () => dyn.dateMs,
        () => dyn.dateMillis,
        () => dyn.date_ms,
        () => dyn.createdAtMs,
        () => dyn.createdAt,
        () => dyn.timestampMs,
        () => dyn.timestamp,
        () => dyn.date,
      ];

      for (final getter in candidates) {
        try {
          final v = getter();
          if (v == null) continue;
          if (v is int) return v;
          if (v is num) return v.toInt();
          if (v is DateTime) return v.millisecondsSinceEpoch;
          final parsed = int.tryParse(v.toString());
          if (parsed != null) return parsed;
        } catch (_) {
          // tenta o próximo nome
        }
      }
    } catch (_) {}

    // fallback: "agora"
    return DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;

    return Scaffold(
      appBar: AppBar(title: Text('Abastecimentos — ${v.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.local_gas_station),
        label: const Text('Novo abastecimento'),
      ),
      body: FutureBuilder<List<FuelLog>>(
        future: _load(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return _ErrorState(
              title: 'Erro ao carregar abastecimentos',
              message: snap.error.toString(),
              onRetry: () => setState(() {}),
            );
          }

          final rawLogs = snap.data ?? const <FuelLog>[];

          if (rawLogs.isEmpty) {
            return _EmptyState(onAdd: _openAdd);
          }

          // ✅ garante que o "último" seja realmente o mais recente (ordena por data desc)
          final logs = [...rawLogs];
          logs.sort((a, b) => _getDateMs(b).compareTo(_getDateMs(a)));

          // Stats gerais
          final spent = logs.fold<double>(0, (s, l) => s + l.totalAmount);
          final liters = logs.fold<double>(0, (s, l) => s + l.liters);

          final kmlValues = logs
              .where((l) => l.kmPerLiter != null && l.kmPerLiter! > 0)
              .map((l) => l.kmPerLiter!)
              .toList();

          final avgKml = kmlValues.isEmpty
              ? null
              : kmlValues.reduce((a, b) => a + b) / kmlValues.length;

          final lastKml = logs.first.kmPerLiter;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              _StatsCard(
                spent: spent,
                liters: liters,
                avgKml: avgKml,
                lastKml: lastKml,
              ),
              const SizedBox(height: 12),
              ...logs.map((l) => _FuelLogTile(log: l, dateMs: _getDateMs(l))),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_gas_station, size: 44),
            const SizedBox(height: 10),
            Text(
              'Nenhum abastecimento registrado ainda.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Colors.black.withOpacity(0.85),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toque em "Novo abastecimento" para começar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Novo abastecimento'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final double spent;
  final double liters;
  final double? avgKml;
  final double? lastKml;

  const _StatsCard({
    required this.spent,
    required this.liters,
    required this.avgKml,
    required this.lastKml,
  });

  String _money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withOpacity(0.6),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    String fmtKml(double? v) {
      if (v == null) return '—';
      return '${v.toStringAsFixed(2).replaceAll('.', ',')} km/L';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Resumo',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat('Gasto total', _money(spent)),
              const SizedBox(width: 10),
              stat(
                'Litros',
                '${liters.toStringAsFixed(1).replaceAll('.', ',')} L',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat('Média', fmtKml(avgKml)),
              const SizedBox(width: 10),
              stat('Último', fmtKml(lastKml)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Obs: o km/L só é calculado a partir do 2º abastecimento (comparando com o odômetro anterior).',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _FuelLogTile extends StatelessWidget {
  final FuelLog log;
  final int dateMs;
  const _FuelLogTile({required this.log, required this.dateMs});

  String _money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  String _n(double v, {int p = 1}) => v.toStringAsFixed(p).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    final kml = log.kmPerLiter == null
        ? '—'
        : '${_n(log.kmPerLiter!, p: 2)} km/L';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.local_gas_station),
        title: Text('${_money(log.totalAmount)} • ${_n(log.liters)} L'),
        subtitle: Text(
          '$dateStr\n'
          'Odômetro: ${_n(log.odometer, p: 1)} km • '
          'Preço/L: ${_money(log.pricePerLiter)} • '
          'km/L: $kml',
        ),
        isThreeLine: true,
      ),
    );
  }
}
