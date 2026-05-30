import 'package:flutter/material.dart';
import 'models/vehicle.dart';
import 'repositories/vehicle_repository.dart';

class AddVehiclePage extends StatefulWidget {
  const AddVehiclePage({super.key});

  @override
  State<AddVehiclePage> createState() => _AddVehiclePageState();
}

class _AddVehiclePageState extends State<AddVehiclePage> {
  final _repo = VehicleRepository();

  final _nameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();

  String _type = 'car'; // 'car' | 'motorcycle'
  String _fuelType = 'gasolina'; // 'gasolina' | 'etanol' | 'diesel'

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  bool get _canSave {
    if (_saving) return false;
    return _nameCtrl.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final plate = _plateCtrl.text.trim();

    if (name.isEmpty) {
      _toast('Informe o nome do veículo.');
      return;
    }

    setState(() => _saving = true);
    try {
      final v = Vehicle(
        name: name,
        type: _type,
        plate: plate.isEmpty ? null : plate,
        fuelType: _fuelType,
        createdAt: DateTime.now(),
      );

      await _repo.insert(v);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Erro ao salvar veículo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _deco(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.03),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar veículo'),
        actions: [
          TextButton.icon(
            onPressed: _canSave ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Salvar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _canSave ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text(
                'Salvar veículo',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Dados do veículo',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: _deco(
                    'Nome',
                    hint: 'Ex: HB20, Carro, CG 160, Moto…',
                    icon: Icons.directions_car,
                  ),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: _deco('Tipo', icon: Icons.category),
                  items: const [
                    DropdownMenuItem(value: 'car', child: Text('Carro')),
                    DropdownMenuItem(value: 'motorcycle', child: Text('Moto')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'car'),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  initialValue: _fuelType,
                  decoration: _deco(
                    'Combustível',
                    icon: Icons.local_gas_station,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'gasolina',
                      child: Text('Gasolina'),
                    ),
                    DropdownMenuItem(value: 'etanol', child: Text('Etanol')),
                    DropdownMenuItem(value: 'diesel', child: Text('Diesel')),
                  ],
                  onChanged: (v) => setState(() => _fuelType = v ?? 'gasolina'),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _plateCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: _deco(
                    'Placa (opcional)',
                    hint: 'Ex: ABC1D23',
                    icon: Icons.confirmation_number_outlined,
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
