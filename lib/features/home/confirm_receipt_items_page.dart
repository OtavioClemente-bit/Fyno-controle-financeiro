import 'package:flutter/material.dart';

import 'receipt_item_draft.dart';

class ConfirmReceiptItemsPage extends StatefulWidget {
  final List<ReceiptItemDraft> initialItems;

  const ConfirmReceiptItemsPage({super.key, required this.initialItems});

  @override
  State<ConfirmReceiptItemsPage> createState() =>
      _ConfirmReceiptItemsPageState();
}

class _ConfirmReceiptItemsPageState extends State<ConfirmReceiptItemsPage> {
  late final List<ReceiptItemDraft> _items = widget.initialItems
      .map((e) => e.copy())
      .toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Conferir itens (${_items.length})'),
        centerTitle: false,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                'Ajuste nome, preço unitário e quantidade. '
                'Quando vier do QR do portal, a unidade (UN/kg/PT) aparece ao lado.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.7),
                  height: 1.2,
                ),
              ),
            );
          }

          final item = _items[i - 1];
          return _ItemCard(
            item: item,
            onDelete: () => setState(() => _items.removeAt(i - 1)),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                final cleaned = _items
                    .where((e) => e.name.trim().isNotEmpty && e.price > 0)
                    .toList();
                Navigator.pop(context, cleaned);
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar itens'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  final ReceiptItemDraft item;
  final VoidCallback onDelete;

  const _ItemCard({required this.item, required this.onDelete});

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.item.name,
  );

  late final TextEditingController _priceCtrl = TextEditingController(
    text: widget.item.price == 0
        ? ''
        : widget.item.price.toStringAsFixed(2).replaceAll('.', ','),
  );

  late final TextEditingController _qtyCtrl = TextEditingController(
    text: widget.item.qty == null
        ? ''
        : widget.item.qty!.toStringAsFixed(4).replaceAll('.', ','),
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  double _parsePrice(String s) {
    var v = s.trim();
    v = v.replaceAll(' ', '');
    // pt-BR: 1.234,56
    if (v.contains(',')) {
      v = v.replaceAll('.', '');
      v = v.replaceAll(',', '.');
    }
    return double.tryParse(v) ?? 0;
  }

  double? _parseQty(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    // qty vem como 1.2500 ou 1,2500
    final v = t.replaceAll(',', '.');
    return double.tryParse(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final unit = (widget.item.unit ?? '').trim();
    final hasUnit = unit.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Produto',
                    hintText: 'Ex: Banana caturra',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => widget.item.name = v,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Remover item',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Preço unitário (R\$)',
                    hintText: '0,00',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => widget.item.price = _parsePrice(v),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Qtd',
                    hintText: '1,0000',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => widget.item.qty = _parseQty(v),
                ),
              ),
              const SizedBox(width: 10),
              if (hasUnit)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    unit.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '--',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
