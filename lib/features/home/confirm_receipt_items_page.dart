import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/adaptive_pair.dart';
import 'product_name_ai_service.dart';
import 'product_name_clipboard_ai.dart';
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
  bool _improvingNames = false;
  int _namesRevision = 0;
  String? _improvementMessage;

  Future<void> _improveProductNames() async {
    if (_items.isEmpty || _improvingNames) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _improvingNames = true;
      _improvementMessage = null;
    });

    final result = await ProductNameAiService.enhance(
      _items.map((item) => item.name).toList(growable: false),
    );
    if (!mounted) return;

    setState(() {
      for (final enhanced in result.products) {
        if (enhanced.index < 0 || enhanced.index >= _items.length) continue;
        final item = _items[enhanced.index];
        item.name = enhanced.professionalName;
        item.nameSource = enhanced.origin == ProductNameEnhancementOrigin.ai
            ? ProductNameSource.ai
            : ProductNameSource.local;
      }
      _namesRevision++;
      _improvementMessage = result.message;
      _improvingNames = false;
    });
  }

  Future<void> _openClipboardAi() async {
    if (_items.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final prompt = ProductNameClipboardAi.buildPrompt(
      _items.map((item) => item.originalName).toList(growable: false),
    );
    final responseController = TextEditingController();
    String? error;

    final imported = await showModalBottomSheet<ClipboardAiImportResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Melhorar com IA — sem API',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  '1. Copie o pedido e envie ao ChatGPT ou outra IA.\n'
                  '2. Copie a resposta completa e cole abaixo.\n'
                  '3. O Fyno valida os IDs antes de alterar os produtos.',
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: prompt));
                    if (!sheetContext.mounted) return;
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text('Pedido copiado. Agora envie para a IA.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_all_rounded),
                  label: Text('Copiar pedido (${_items.length} produtos)'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: responseController,
                  minLines: 5,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: 'Resposta da IA',
                    hintText: '[{"id": 1, "nome": "..."}]',
                    border: const OutlineInputBorder(),
                    errorText: error,
                    suffixIcon: IconButton(
                      tooltip: 'Colar da área de transferência',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        responseController.text = data?.text ?? '';
                        setSheetState(() => error = null);
                      },
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    try {
                      final result = ProductNameClipboardAi.parseResponse(
                        responseController.text,
                        itemCount: _items.length,
                      );
                      Navigator.of(sheetContext).pop(result);
                    } on FormatException catch (exception) {
                      setSheetState(() => error = exception.message);
                    } catch (_) {
                      setSheetState(
                        () => error =
                            'Resposta inválida. Copie novamente o JSON da IA.',
                      );
                    }
                  },
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Validar e aplicar nomes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    responseController.dispose();
    if (!mounted || imported == null) return;

    setState(() {
      for (final entry in imported.namesByIndex.entries) {
        final item = _items[entry.key];
        item.name = entry.value;
        item.nameSource = ProductNameSource.ai;
      }
      _namesRevision++;
      final applied = imported.namesByIndex.length;
      _improvementMessage = imported.ignoredEntries == 0
          ? '$applied nome(s) importado(s) e validado(s) com IA.'
          : '$applied nome(s) aplicados; ${imported.ignoredEntries} resposta(s) inválida(s) ignorada(s).';
    });
  }

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
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primaryContainer.withValues(alpha: .78),
                        cs.tertiaryContainer.withValues(alpha: .48),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: .18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.auto_awesome, color: cs.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ProductNameAiService.isAiConfigured
                                      ? 'Nomes com IA'
                                      : 'Nomes inteligentes',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  ProductNameAiService.isAiConfigured
                                      ? 'Transforma abreviações da nota em nomes claros e profissionais.'
                                      : 'Corrige abreviações comuns no próprio aparelho.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: cs.onSurface.withValues(alpha: .7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: _improvingNames
                              ? null
                              : _improveProductNames,
                          icon: _improvingNames
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.auto_fix_high_rounded),
                          label: Text(
                            _improvingNames
                                ? 'Melhorando nomes…'
                                : 'Melhorar nomes dos produtos',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openClipboardAi,
                          icon: const Icon(Icons.content_paste_go_rounded),
                          label: const Text('Usar IA copiando e colando'),
                        ),
                      ),
                      if (_improvementMessage != null) ...[
                        const SizedBox(height: 9),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 17,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                _improvementMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.25,
                                  color: cs.onSurface.withValues(alpha: .72),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'Confira as sugestões antes de salvar. O nome original da nota '
                    'fica visível e pode ser restaurado a qualquer momento.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.7),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            );
          }

          final item = _items[i - 1];
          return _ItemCard(
            item: item,
            namesRevision: _namesRevision,
            onDelete: () => setState(() => _items.removeAt(i - 1)),
            onRestoreOriginal: () {
              setState(() {
                item.restoreOriginalName();
                _namesRevision++;
              });
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: SizedBox(
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
  final int namesRevision;
  final VoidCallback onDelete;
  final VoidCallback onRestoreOriginal;

  const _ItemCard({
    required this.item,
    required this.namesRevision,
    required this.onDelete,
    required this.onRestoreOriginal,
  });

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
  void didUpdateWidget(covariant _ItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.namesRevision != widget.namesRevision &&
        _nameCtrl.text != widget.item.name) {
      _nameCtrl.value = TextEditingValue(
        text: widget.item.name,
        selection: TextSelection.collapsed(offset: widget.item.name.length),
      );
    }
  }

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

  String _money(double value) =>
      'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceAll('.', ',');
  }

  void _syncPriceController() {
    final value = widget.item.price.toStringAsFixed(2).replaceAll('.', ',');
    _priceCtrl.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final unit = (widget.item.unit ?? '').trim();
    final hasUnit = unit.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
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
                  onChanged: (v) {
                    widget.item.name = v;
                    widget.item.nameSource =
                        v.trim().toLowerCase() ==
                            widget.item.originalName.trim().toLowerCase()
                        ? ProductNameSource.receipt
                        : ProductNameSource.manual;
                  },
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
          if (widget.item.hasRenamedProduct) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.item.nameSource == ProductNameSource.ai
                        ? Icons.auto_awesome
                        : Icons.spellcheck_rounded,
                    size: 17,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Na nota: ${widget.item.originalName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        color: cs.onSurface.withValues(alpha: .7),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Restaurar nome da nota',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onRestoreOriginal,
                    icon: const Icon(Icons.undo_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          AdaptivePair(
            first: TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Preço por unidade (R\$)',
                hintText: '0,00',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                setState(() => widget.item.setUnitPrice(_parsePrice(v)));
              },
            ),
            second: TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantidade',
                hintText: '1,0000',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                final previousPrice = widget.item.price;
                setState(() => widget.item.setQuantity(_parseQty(v)));
                if (widget.item.price != previousPrice) {
                  _syncPriceController();
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.item.wasUnitPriceCalculated
                  ? cs.primaryContainer.withValues(alpha: .42)
                  : cs.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.item.wasUnitPriceCalculated
                    ? cs.primary.withValues(alpha: .24)
                    : cs.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.item.wasUnitPriceCalculated
                      ? Icons.calculate_rounded
                      : Icons.receipt_long_rounded,
                  size: 19,
                  color: widget.item.wasUnitPriceCalculated
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.wasUnitPriceCalculated
                            ? 'Preço unitário calculado automaticamente'
                            : 'Total desta linha',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.item.wasUnitPriceCalculated
                            ? '${_money(widget.item.effectiveLineTotal)} ÷ '
                                  '${_quantity(widget.item.effectiveQty)} = '
                                  '${_money(widget.item.price)} cada'
                            : '${_quantity(widget.item.effectiveQty)} × '
                                  '${_money(widget.item.price)} = '
                                  '${_money(widget.item.effectiveLineTotal)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: .72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(
                  alpha: hasUnit ? .7 : .35,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                hasUnit ? 'Unidade: ${unit.toUpperCase()}' : 'Unidade: --',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: hasUnit
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: .55),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
