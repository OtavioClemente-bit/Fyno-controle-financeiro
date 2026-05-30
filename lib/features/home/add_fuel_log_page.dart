import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:controle_financeiro/shared/format/format_br.dart';
import 'package:controle_financeiro/shared/input_formatters/currency_ptbr_input_formatter.dart';

import 'models/vehicle.dart';
import 'models/fuel_log.dart';
import 'models/tx_item.dart';
import 'repositories/fuel_log_repository.dart';
import 'repositories/tx_repository.dart';

class AddFuelLogPage extends StatefulWidget {
  final Vehicle vehicle;
  const AddFuelLogPage({super.key, required this.vehicle});

  @override
  State<AddFuelLogPage> createState() => _AddFuelLogPageState();
}

class _AddFuelLogPageState extends State<AddFuelLogPage> {
  final FuelLogRepository _fuelRepo = FuelLogRepository();
  final TxRepository _txRepo = TxRepository();

  final _odoCtrl = TextEditingController();
  final _litersCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  bool _saving = false;

  double? _parseNum(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  double? _parseMoney(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final cleaned = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleaned);
  }

  double get _total {
    final liters = _parseNum(_litersCtrl.text) ?? 0;
    final price = _parseMoney(_priceCtrl.text) ?? 0;
    return liters * price;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      helpText: 'Selecionar data',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ✅ tenta criar FuelLog mesmo que o model esteja com nomes diferentes
  FuelLog _buildFuelLog({
    required int vehicleId,
    required int dateMs,
    required double odometer,
    required double liters,
    required double pricePerLiter,
    required double totalAmount,
    required double? kmPerLiter,
    required String noteText,
  }) {
    final dynCtor = FuelLog as dynamic;

    // Tenta o construtor com dateMs (se existir)
    try {
      return dynCtor(
            id: null,
            vehicleId: vehicleId,
            dateMs: dateMs,
            odometer: odometer,
            liters: liters,
            pricePerLiter: pricePerLiter,
            totalAmount: totalAmount,
            kmPerLiter: kmPerLiter,
            note: noteText.isEmpty ? null : noteText,
          )
          as FuelLog;
    } catch (_) {}

    // Tenta com dateMillis
    try {
      return dynCtor(
            id: null,
            vehicleId: vehicleId,
            dateMillis: dateMs,
            odometer: odometer,
            liters: liters,
            pricePerLiter: pricePerLiter,
            totalAmount: totalAmount,
            kmPerLiter: kmPerLiter,
            note: noteText.isEmpty ? null : noteText,
          )
          as FuelLog;
    } catch (_) {}

    // Tenta com date (int)
    try {
      return dynCtor(
            id: null,
            vehicleId: vehicleId,
            date: dateMs,
            odometer: odometer,
            liters: liters,
            pricePerLiter: pricePerLiter,
            totalAmount: totalAmount,
            kmPerLiter: kmPerLiter,
            note: noteText.isEmpty ? null : noteText,
          )
          as FuelLog;
    } catch (_) {}

    // Se note não aceitar null, manda string vazia
    try {
      return dynCtor(
            id: null,
            vehicleId: vehicleId,
            dateMs: dateMs,
            odometer: odometer,
            liters: liters,
            pricePerLiter: pricePerLiter,
            totalAmount: totalAmount,
            kmPerLiter: kmPerLiter,
            note: noteText,
          )
          as FuelLog;
    } catch (_) {}

    // Último fallback (pra te mostrar exatamente o erro de assinatura)
    throw Exception('FuelLog constructor não bate com os parâmetros usados.');
  }

  Future<void> _save() async {
    final odo = _parseNum(_odoCtrl.text);
    final liters = _parseNum(_litersCtrl.text);
    final price = _parseMoney(_priceCtrl.text);

    if (odo == null || odo <= 0) return _toast('Informe o odômetro.');
    if (liters == null || liters <= 0) return _toast('Informe os litros.');
    if (price == null || price <= 0) {
      return _toast('Informe o preço por litro.');
    }

    setState(() => _saving = true);

    try {
      final prev = await _fuelRepo.getPreviousLog(widget.vehicle.id!, _date);
      double? kmPerLiter;

      if (prev != null && odo > prev.odometer) {
        final dist = odo - prev.odometer;
        kmPerLiter = dist / liters;
      }

      final totalAmount = liters * price;
      final noteText = _noteCtrl.text.trim();

      final log = _buildFuelLog(
        vehicleId: widget.vehicle.id!,
        dateMs: _date.millisecondsSinceEpoch,
        odometer: odo,
        liters: liters,
        pricePerLiter: price,
        totalAmount: totalAmount,
        kmPerLiter: kmPerLiter,
        noteText: noteText,
      );

      await _fuelRepo.insert(log);

      // ✅ entra no extrato normal também
      final tx = TxItem(
        title: 'Abastecimento — ${widget.vehicle.name}',
        amount: totalAmount,
        isIncome: false,
        date: _date,
        category: 'Combustível',
        note: [
          'Veículo: ${widget.vehicle.name}',
          'Odômetro: ${odo.toStringAsFixed(1).replaceAll('.', ',')} km',
          'Litros: ${liters.toStringAsFixed(2).replaceAll('.', ',')} L',
          'Preço/L: R\$ ${price.toStringAsFixed(3).replaceAll('.', ',')}',
          if (kmPerLiter != null)
            'Consumo: ${kmPerLiter.toStringAsFixed(2).replaceAll('.', ',')} km/L',
          if (noteText.isNotEmpty) 'Obs: $noteText',
        ].join(' • '),
        receiptImagePath: null,
        paymentMethod: 'pix',
        creditCardId: null,
        installments: null,
      );

      await _txRepo.insert(tx);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Erro ao salvar abastecimento: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _odoCtrl.dispose();
    _litersCtrl.dispose();
    _priceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final totalStr = 'R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Novo abastecimento — ${widget.vehicle.name}'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Salvar'),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Dados do abastecimento',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  const SizedBox(height: 12),

                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(16),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Data',
                        prefixIcon: const Icon(Icons.calendar_month),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(FormatBR.date(_date)),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _odoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Odômetro (km)',
                      prefixIcon: const Icon(Icons.speed),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _litersCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Litros (L)',
                      prefixIcon: const Icon(Icons.opacity),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyPtBrInputFormatter(),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Preço por litro (R\$)',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Total: $totalStr',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Observação (opcional)',
                      prefixIcon: const Icon(Icons.note_alt),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'O app calcula automaticamente o km/L comparando com o último odômetro salvo.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
