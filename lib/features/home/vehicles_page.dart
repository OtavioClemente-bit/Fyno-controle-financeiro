import 'package:flutter/material.dart';
import 'add_vehicle_page.dart';
import 'models/vehicle.dart';
import 'repositories/vehicle_repository.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  final _repo = VehicleRepository();

  bool _loading = true;
  List<Vehicle> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _repo.getAll();
      if (!mounted) return;
      setState(() => _items = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goAdd() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddVehiclePage()),
    );

    if (ok == true) {
      await _load();
    }
  }

  String _typeLabel(String t) => t == 'motorcycle' ? 'Moto' : 'Carro';

  IconData _typeIcon(String t) =>
      t == 'motorcycle' ? Icons.two_wheeler : Icons.directions_car;

  Future<void> _confirmDelete(Vehicle v) async {
    if (v.id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover veículo'),
        content: Text(
          'Deseja remover "${v.name}"?\n\n'
          'Os abastecimentos desse veículo também serão removidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _repo.delete(v.id!);
    if (!mounted) return;
    await _load();
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_gas_station,
              size: 56,
              color: Colors.black.withOpacity(0.35),
            ),
            const SizedBox(height: 10),
            const Text(
              'Nenhum veículo cadastrado',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Cadastre seu carro e sua moto para controlar abastecimentos e consumo (km/L).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withOpacity(0.6)),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _goAdd,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar veículo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Vehicle v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.black.withOpacity(0.05),
            child: Icon(_typeIcon(v.type)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_typeLabel(v.type)} • ${v.fuelType}${(v.plate ?? '').trim().isEmpty ? '' : ' • ${v.plate}'}',
                  style: TextStyle(color: Colors.black.withOpacity(0.6)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmDelete(v),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Veículos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Adicionar',
            onPressed: _goAdd,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goAdd,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_items.isEmpty
                ? _empty()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: _items.map(_tile).toList(),
                  )),
    );
  }
}
