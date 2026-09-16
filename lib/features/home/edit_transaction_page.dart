import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:controle_financeiro/core/db/app_db.dart';
import 'package:controle_financeiro/shared/widgets/adaptive_pair.dart';

import 'models/tx_item.dart';
import 'repositories/tx_repository.dart';
import 'receipt_image_store.dart';
import 'accounts_cards_repository.dart';

class EditTransactionPage extends StatefulWidget {
  final TxItem tx;
  const EditTransactionPage({super.key, required this.tx});

  @override
  State<EditTransactionPage> createState() => _EditTransactionPageState();
}

class _EditTransactionPageState extends State<EditTransactionPage> {
  final TxRepository _repo = TxRepository();
  final AccountsCardsRepository _accountsCardsRepository =
      AccountsCardsRepository();
  List<CreditCardItem> _creditCards = const [];
  int? _creditCardId;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _noteCtrl;

  late DateTime _date;
  late String _category;
  late String _paymentMethod;
  String? _imagePath;

  // Snapshot inicial para detectar alterações
  late final String _initialTitle;
  late final String _initialValueText;
  late final String _initialNote;
  late final DateTime _initialDate;
  late final String _initialCategory;
  late final String _initialPaymentMethod;
  late final int? _initialCreditCardId;
  late final String? _initialImagePath;

  bool _isSaving = false;

  final _picker = ImagePicker();

  static const List<String> _defaultCategories = [
    'Mercado',
    'Combustível',
    'Casa',
    'Saúde',
    'Lazer',
    'Transporte',
    'Outros',
  ];

  static const List<String> _paymentMethods = [
    'Pix',
    'Débito',
    TxItem.creditPaymentMethod,
    'Dinheiro',
    TxItem.creditCardBillPaymentMethod,
  ];

  /// Lista de categorias exibida no dropdown (padrão + categorias do banco).
  /// Mantém a ordem das categorias padrão e acrescenta as customizadas em ordem alfabética.
  List<String> _categories = List<String>.from(_defaultCategories);

  bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();

    _titleCtrl = TextEditingController(text: widget.tx.title);
    _valueCtrl = TextEditingController(
      text: widget.tx.amount.toStringAsFixed(2),
    );
    _noteCtrl = TextEditingController(text: widget.tx.note ?? '');

    _date = widget.tx.date;
    _category = widget.tx.category.trim();
    _paymentMethod = _paymentMethods.contains(widget.tx.paymentMethod)
        ? widget.tx.paymentMethod
        : 'Pix';
    _creditCardId = widget.tx.creditCardId;

    if (_category.isEmpty) {
      _category = _defaultCategories.first;
    }

    // Garante que a categoria atual exista na lista antes do primeiro build (evita crash do Dropdown)

    final baseCats = List<String>.from(_defaultCategories);

    final currentLower = _category.toLowerCase();

    if (!baseCats.any((c) => c.trim().toLowerCase() == currentLower)) {
      baseCats.insert(0, _category);
    }

    _categories = baseCats;
    _imagePath = widget.tx.receiptImagePath;

    _initialTitle = widget.tx.title;
    _initialValueText = widget.tx.amount.toStringAsFixed(2);
    _initialNote = widget.tx.note ?? '';
    _initialDate = widget.tx.date;
    _initialCategory = widget.tx.category;
    _initialPaymentMethod = _paymentMethod;
    _initialCreditCardId = _creditCardId;
    _initialImagePath = widget.tx.receiptImagePath;

    _titleCtrl.addListener(_refresh);
    _valueCtrl.addListener(_refresh);
    _noteCtrl.addListener(_refresh);

    _loadCategories();
    _loadCreditCards();
  }

  Future<void> _loadCreditCards() async {
    final cards = await _accountsCardsRepository.getCards();
    if (mounted) setState(() => _creditCards = cards);
  }

  Future<void> _loadCategories() async {
    try {
      final names = await AppDb.getCategoryNames();

      // Defaults preservam a ordem original.
      final defaultsLower = _defaultCategories
          .map((e) => e.trim().toLowerCase())
          .toSet();

      // Customizadas do banco (sem duplicar defaults / sem vazios).
      final custom = <String>[];
      final seenCustomLower = <String>{};
      for (final n in names) {
        final name = n.trim();
        if (name.isEmpty) continue;
        final lower = name.toLowerCase();
        if (defaultsLower.contains(lower)) continue;
        if (seenCustomLower.contains(lower)) continue;
        seenCustomLower.add(lower);
        custom.add(name);
      }
      custom.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      // Merge final, garantindo unicidade (case-insensitive) para evitar crash do Dropdown.
      final merged = <String>[];
      final seenMergedLower = <String>{};
      for (final n in [..._defaultCategories, ...custom]) {
        final name = n.trim();
        if (name.isEmpty) continue;
        final lower = name.toLowerCase();
        if (seenMergedLower.contains(lower)) continue;
        seenMergedLower.add(lower);
        merged.add(name);
      }

      // Garante que a categoria atual apareça (caso tenha sido removida do banco).
      final current = _category.trim();
      if (current.isNotEmpty &&
          !merged.any((e) => e.toLowerCase() == current.toLowerCase())) {
        merged.insert(0, current);
      }

      if (!mounted) return;
      setState(() {
        _categories = merged;
        _loadingCategories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categories = List<String>.from(_defaultCategories);
        _loadingCategories = false;
      });
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_refresh);
    _valueCtrl.removeListener(_refresh);
    _noteCtrl.removeListener(_refresh);

    _titleCtrl.dispose();
    _valueCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  bool get _hasChanges {
    final title = _titleCtrl.text.trim();
    final value = _valueCtrl.text.trim();
    final note = _noteCtrl.text;
    return title != _initialTitle.trim() ||
        value != _initialValueText.trim() ||
        note != _initialNote ||
        _date != _initialDate ||
        _category != _initialCategory ||
        _paymentMethod != _initialPaymentMethod ||
        _creditCardId != _initialCreditCardId ||
        _imagePath != _initialImagePath;
  }

  bool get _canSave {
    if (_isSaving) return false;
    if (!_hasChanges) return false;

    final title = _titleCtrl.text.trim();
    final valueText = _valueCtrl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(valueText);

    if (title.isEmpty) return false;
    if (amount == null || amount <= 0) return false;
    if (!widget.tx.isIncome &&
        (_paymentMethod == TxItem.creditPaymentMethod ||
            _paymentMethod == TxItem.creditCardBillPaymentMethod) &&
        _creditCardId == null) {
      return false;
    }

    return true;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
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

  Future<void> _pickImage(ImageSource source) async {
    final xfile = await _picker.pickImage(source: source, imageQuality: 85);
    if (xfile != null && mounted) setState(() => _imagePath = xfile.path);
  }

  Future<void> _openImagePreview() async {
    if (_imagePath == null) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Container(
                  color: Colors.black,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Center(
                      child: Image.file(File(_imagePath!), fit: BoxFit.contain),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
          'Você fez mudanças que ainda não foram salvas. '
          'Se voltar agora, você vai perder essas alterações.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar editando'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _handleBack() async {
    final canLeave = await _confirmDiscardChanges();
    if (!mounted) return;
    if (canLeave) Navigator.pop(context, false);
  }

  Future<void> _confirmRemoveImage() async {
    if (_imagePath == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover imagem'),
        content: const Text('Deseja realmente remover o comprovante?'),
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

    if (ok == true && mounted) {
      setState(() => _imagePath = null);
    }
  }

  Future<void> _save() async {
    if (widget.tx.id == null) {
      _toast('Erro: transação sem ID.');
      return;
    }

    final title = _titleCtrl.text.trim();
    final valueText = _valueCtrl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(valueText);

    if (title.isEmpty) {
      _toast('Informe a descrição.');
      return;
    }
    if (amount == null || amount <= 0) {
      _toast('Informe um valor válido.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final storedImagePath = _imagePath == _initialImagePath
          ? _imagePath
          : await ReceiptImageStore.persist(_imagePath);
      final updated = TxItem(
        id: widget.tx.id,
        title: title,
        amount: amount,
        isIncome: widget.tx.isIncome,
        date: _date,
        category: _category,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        receiptImagePath: storedImagePath,
        paymentMethod: widget.tx.isIncome
            ? widget.tx.paymentMethod
            : _paymentMethod,
        creditCardId:
            !widget.tx.isIncome &&
                (_paymentMethod == TxItem.creditPaymentMethod ||
                    _paymentMethod == TxItem.creditCardBillPaymentMethod)
            ? _creditCardId
            : null,
        installments: widget.tx.installments,
        accountId: widget.tx.accountId,
      );
      await _repo.update(updated);
      if (_initialImagePath != storedImagePath) {
        await ReceiptImageStore.deleteIfManaged(_initialImagePath);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------- UI helpers
  InputDecoration _inputDeco({
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      filled: true,
      fillColor: cs.surfaceContainerHigh,
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titlePage = widget.tx.isIncome ? 'Editar Receita' : 'Editar Despesa';
    final cs = Theme.of(context).colorScheme;
    final compactAppBar =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.25;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text(titlePage),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          actions: compactAppBar
              ? null
              : [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: TextButton.icon(
                      onPressed: _canSave ? _save : null,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Salvar'),
                    ),
                  ),
                ],
        ),

        // ✅ Botão fixo embaixo (cara de app premium)
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text(
                      'Salvar alterações',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedOpacity(
                  opacity: _hasChanges ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    _hasChanges ? 'Você tem alterações não salvas.' : '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            // CARD: Dados
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .55),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                    color: cs.shadow.withValues(alpha: .05),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader('Dados'),
                  TextField(
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: _inputDeco(
                      label: 'Descrição',
                      hint: 'Ex: Almoço, Uber, Salário...',
                      prefixIcon: const Icon(Icons.edit),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _valueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inputDeco(
                      label: 'Valor',
                      hint: 'Ex: 59.90',
                      prefixIcon: const Icon(Icons.attach_money),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptivePair(
                    first: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(16),
                      child: InputDecorator(
                        decoration: _inputDeco(
                          label: 'Data',
                          prefixIcon: const Icon(Icons.calendar_month),
                        ),
                        child: Text(_fmtDate(_date)),
                      ),
                    ),
                    second: DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: _inputDeco(
                        label: 'Categoria',
                        prefixIcon: const Icon(Icons.category),
                        suffixIcon: _loadingCategories
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: _loadingCategories
                          ? null
                          : (v) {
                              if (v != null && mounted) {
                                setState(() => _category = v);
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (!widget.tx.isIncome) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: .55),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionHeader('Forma de pagamento'),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: _inputDeco(
                        label: 'Pagamento',
                        prefixIcon: const Icon(Icons.credit_card_rounded),
                      ),
                      items: _paymentMethods
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _paymentMethod = value);
                        }
                      },
                    ),
                    if (_paymentMethod == TxItem.creditPaymentMethod ||
                        _paymentMethod ==
                            TxItem.creditCardBillPaymentMethod) ...[
                      const SizedBox(height: 10),
                      if (_creditCards.isEmpty)
                        const Text(
                          'Cadastre um cartão na Central de Contas e Cartões.',
                        )
                      else
                        DropdownButtonFormField<int>(
                          initialValue: _creditCardId,
                          isExpanded: true,
                          decoration: _inputDeco(
                            label: 'Cartão',
                            prefixIcon: const Icon(Icons.credit_card_rounded),
                          ),
                          items: _creditCards
                              .map(
                                (card) => DropdownMenuItem(
                                  value: card.id,
                                  child: Text(card.displayName),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _creditCardId = value),
                        ),
                    ],
                    if (_paymentMethod ==
                        TxItem.creditCardBillPaymentMethod) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Este valor quita compras no crédito e não será somado novamente como despesa.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // CARD: Comprovante
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .55),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                    color: cs.shadow.withValues(alpha: .05),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader(
                    'Comprovante (foto)',
                    subtitle: _imagePath != null ? 'Toque para ampliar' : null,
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _imagePath != null
                        ? InkWell(
                            key: const ValueKey('img'),
                            onTap: _openImagePreview,
                            borderRadius: BorderRadius.circular(18),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                color: cs.surfaceContainerHighest,
                                height: 190,
                                child: Image.file(
                                  File(_imagePath!),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            key: const ValueKey('empty'),
                            height: 190,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: const Text('Nenhuma imagem selecionada'),
                          ),
                  ),
                  const SizedBox(height: 10),
                  AdaptivePair(
                    gap: 10,
                    first: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Câmera'),
                    ),
                    second: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galeria'),
                    ),
                  ),
                  if (_imagePath != null) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _confirmRemoveImage,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remover imagem'),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // CARD: Observação
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .55),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                    color: cs.shadow.withValues(alpha: .05),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader('Observação'),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    decoration: _inputDeco(
                      label: 'Opcional',
                      hint: 'Ex: pagamento dividido, local, etc.',
                      prefixIcon: const Icon(Icons.note_alt),
                    ),
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
