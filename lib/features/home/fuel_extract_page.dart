import 'package:flutter/material.dart';

import '../../core/db/app_db.dart';
import 'models/fuel_log.dart';

/// Extrato de abastecimentos (fuel_logs)
/// - Resumo (topo): Gasto total + Litros abastecidos (sempre)
/// - Detalhes (aparece ao selecionar veículo): gasto, litros, média km/L, total de registros
/// - Exclusão: swipe para excluir + menu (⋮) com confirmação
class FuelExtractPage extends StatefulWidget {
  const FuelExtractPage({super.key});

  @override
  State<FuelExtractPage> createState() => _FuelExtractPageState();
}

class _FuelExtractPageState extends State<FuelExtractPage> {
  static const int _kNoVehicle = -1; // "Sem veículo / Aleatório"

  bool _loading = true;
  String? _error;

  List<_FuelRow> _rows = [];
  List<_VehicleLite> _vehicles = [];

  /// null = Todos | -1 = Sem veículo | >0 = id do veículo
  int? _vehicleFilterId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await AppDb.instance;

      // veículos
      final vRows = await db.query(
        'vehicles',
        columns: ['id', 'name'],
        orderBy: 'name COLLATE NOCASE ASC',
      );

      final vehicles = vRows
          .map(
            (e) => _VehicleLite(
              id: (e['id'] as num).toInt(),
              name: (e['name'] ?? '').toString(),
            ),
          )
          .toList();

      // fuel logs + vehicle name (join)
      final where = <String>[];
      final args = <Object?>[];

      if (_vehicleFilterId == _kNoVehicle) {
        where.add('f.vehicle_id IS NULL');
      } else if (_vehicleFilterId != null) {
        where.add('f.vehicle_id = ?');
        args.add(_vehicleFilterId);
      }

      final sql =
          '''
        SELECT
          f.*,
          v.name AS vehicle_name
        FROM fuel_logs f
        LEFT JOIN vehicles v ON v.id = f.vehicle_id
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        ORDER BY f.date_ms DESC, f.id DESC
      ''';

      final rows = await db.rawQuery(sql, args);

      final mapped = rows.map((r) {
        final log = FuelLog.fromMap(r);
        final vName = (r['vehicle_name'] ?? '').toString();
        return _FuelRow(log: log, vehicleName: vName.isEmpty ? '—' : vName);
      }).toList();

      setState(() {
        _vehicles = vehicles;
        _rows = mapped;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _getDateMs(FuelLog log) {
    final d = log as dynamic;
    try {
      final v = d.dateMs;
      if (v is int) return v;
    } catch (_) {}
    try {
      final v = d.date_ms;
      if (v is int) return v;
    } catch (_) {}
    // fallback (se o model tiver DateTime)
    try {
      final v = d.date;
      if (v is DateTime) return v.millisecondsSinceEpoch;
    } catch (_) {}
    return DateTime.now().millisecondsSinceEpoch;
  }

  int? _getId(FuelLog log) {
    final d = log as dynamic;
    try {
      final v = d.id;
      if (v is int) return v;
      if (v is num) return v.toInt();
    } catch (_) {}
    try {
      final v = d.fuelLogId;
      if (v is int) return v;
      if (v is num) return v.toInt();
    } catch (_) {}
    return null;
  }

  Future<void> _deleteLog(_FuelRow row) async {
    final id = _getId(row.log);
    if (id == null) {
      _toast('Não foi possível excluir (id não encontrado).');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(
          'Isso vai remover este abastecimento do extrato.\n\n'
          '${row.vehicleName} • ${_money(row.log.totalAmount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final db = await AppDb.instance;
      await db.delete('fuel_logs', where: 'id = ?', whereArgs: [id]);

      if (!mounted) return;
      setState(() {
        _rows.removeWhere((r) => _getId(r.log) == id);
      });

      _toast('Lançamento excluído.');
    } catch (e) {
      _toast('Erro ao excluir: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final spent = _rows.fold<double>(0, (s, r) => s + r.log.totalAmount);
    final liters = _rows.fold<double>(0, (s, r) => s + r.log.liters);

    final isVehicleSelected = _vehicleFilterId != null;
    final detailTitle = _vehicleFilterId == _kNoVehicle
        ? 'Sem veículo'
        : _vehicles
              .where((v) => v.id == _vehicleFilterId)
              .map((v) => v.name)
              .cast<String?>()
              .firstWhere((_) => true, orElse: () => null);

    final kmlValues = _rows
        .where((r) => r.log.kmPerLiter != null && r.log.kmPerLiter! > 0)
        .map((r) => r.log.kmPerLiter!)
        .toList();

    final avgKml = (!isVehicleSelected || kmlValues.isEmpty)
        ? null
        : (kmlValues.reduce((a, b) => a + b) / kmlValues.length);

    final regCount = isVehicleSelected ? _rows.length : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extrato de combustíveis'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const _LoadingState()
          : _error != null
          ? _ErrorState(
              title: 'Erro ao carregar',
              message: _error!,
              onRetry: _load,
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Column(
                    children: [
                      _SummaryCard(spent: spent, liters: liters, money: _money),
                      const SizedBox(height: 12),
                      _FilterBar(
                        vehicles: _vehicles,
                        value: _vehicleFilterId,
                        onChanged: (v) async {
                          setState(() => _vehicleFilterId = v);
                          await _load();
                        },
                      ),
                      if (isVehicleSelected) ...[
                        const SizedBox(height: 12),
                        _VehicleDetailsCard(
                          title: detailTitle ?? 'Veículo',
                          spent: spent,
                          liters: liters,
                          avgKml: avgKml,
                          regCount: regCount ?? 0,
                          money: _money,
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _rows.isEmpty
                      ? const _EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final row = _rows[i];
                            final log = row.log;

                            final date = DateTime.fromMillisecondsSinceEpoch(
                              _getDateMs(log),
                            );
                            final dateStr =
                                '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

                            final kml = log.kmPerLiter == null
                                ? '—'
                                : '${_n(log.kmPerLiter!, p: 2)} km/L';

                            final subtitle = StringBuffer()
                              ..write('$dateStr\n')
                              ..write(
                                'Odômetro: ${_n(log.odometer, p: 1)} km • ',
                              )
                              ..write('Litros: ${_n(log.liters, p: 2)} L • ')
                              ..write(
                                'Preço/L: ${_money(log.pricePerLiter)} • ',
                              )
                              ..write('km/L: $kml');

                            if (log.note != null &&
                                log.note!.trim().isNotEmpty) {
                              subtitle.write('\nObs: ${log.note}');
                            }

                            return Dismissible(
                              key: ValueKey('${_getId(log) ?? i}'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await _deleteLog(row);
                                return false; // remove manualmente após delete
                              },
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.red.withOpacity(0.12),
                                ),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                              ),
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: const Icon(Icons.local_gas_station),
                                  title: Text(
                                    '${row.vehicleName} • ${_money(log.totalAmount)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(subtitle.toString()),
                                  isThreeLine: true,
                                  trailing: PopupMenuButton<_RowAction>(
                                    tooltip: 'Ações',
                                    onSelected: (a) {
                                      if (a == _RowAction.delete) {
                                        _deleteLog(row);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: _RowAction.delete,
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline),
                                            SizedBox(width: 10),
                                            Text('Excluir'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

enum _RowAction { delete }

class _VehicleLite {
  final int id;
  final String name;
  const _VehicleLite({required this.id, required this.name});
}

class _FuelRow {
  final FuelLog log;
  final String vehicleName;
  const _FuelRow({required this.log, required this.vehicleName});
}

class _SummaryCard extends StatelessWidget {
  final double spent;
  final double liters;
  final String Function(double) money;

  const _SummaryCard({
    required this.spent,
    required this.liters,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Gasto total',
                value: money(spent),
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                label: 'Litros abastecidos',
                value: '${_n(liters, p: 2)} L',
                icon: Icons.opacity_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleDetailsCard extends StatelessWidget {
  final String title;
  final double spent;
  final double liters;
  final double? avgKml;
  final int regCount;
  final String Function(double) money;

  const _VehicleDetailsCard({
    required this.title,
    required this.spent,
    required this.liters,
    required this.avgKml,
    required this.regCount,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalhes — $title',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Registros',
                    value: regCount.toString(),
                    icon: Icons.list_alt_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    label: 'Média km/L',
                    value: avgKml == null ? '—' : '${_n(avgKml!, p: 2)} km/L',
                    icon: Icons.speed_outlined,
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Metric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withOpacity(0.03),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
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

class _FilterBar extends StatelessWidget {
  final List<_VehicleLite> vehicles;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _FilterBar({
    required this.vehicles,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.directions_car_filled_outlined, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<int?>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Veículo',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
              const DropdownMenuItem<int?>(
                value: _FuelExtractPageState._kNoVehicle,
                child: Text('Sem veículo (Aleatório)'),
              ),
              ...vehicles.map(
                (v) => DropdownMenuItem<int?>(value: v.id, child: Text(v.name)),
              ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_gas_station_outlined,
              size: 42,
              color: Colors.black.withOpacity(0.45),
            ),
            const SizedBox(height: 10),
            const Text(
              'Nenhum abastecimento encontrado',
              style: TextStyle(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Cadastre um abastecimento para ele aparecer aqui.',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
              textAlign: TextAlign.center,
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
            Icon(
              Icons.error_outline,
              size: 42,
              color: Colors.red.withOpacity(0.8),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
              textAlign: TextAlign.center,
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

// ===== helpers =====

String _money(double v) {
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  final parts = s.split(',');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return 'R\$ $intPart,${parts[1]}';
}

String _n(double v, {int p = 2}) {
  final s = v.toStringAsFixed(p).replaceAll('.', ',');
  return s;
}
