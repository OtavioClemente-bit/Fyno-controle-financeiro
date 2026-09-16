import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/format/format_br.dart';
import '../../shared/widgets/category_picker_field.dart';
import 'finance_visuals.dart';
import 'models/tx_item.dart';
import 'recurring_expense_repository.dart';
import 'accounts_cards_repository.dart';

class RecurringExpensesPage extends StatefulWidget {
  const RecurringExpensesPage({super.key});

  @override
  State<RecurringExpensesPage> createState() => _RecurringExpensesPageState();
}

class _RecurringExpensesPageState extends State<RecurringExpensesPage> {
  final _repository = RecurringExpenseRepository();
  final _accountsCardsRepository = AccountsCardsRepository();
  bool _loading = true;
  List<RecurringExpense> _items = const [];
  Set<int> _paidIds = const {};
  List<CreditCardItem> _creditCards = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repository.getAll();
    final cards = await _accountsCardsRepository.getCards();
    final paid = <int>{};
    for (final item in items) {
      if (item.id != null &&
          await _repository.isPaidThisMonth(item, DateTime.now())) {
        paid.add(item.id!);
      }
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _paidIds = paid;
      _creditCards = cards;
      _loading = false;
    });
  }

  DateTime _dueDate(RecurringExpense item) {
    final now = DateTime.now();
    final maxDay = DateTime(now.year, now.month + 1, 0).day;
    return DateTime(now.year, now.month, item.dueDay.clamp(1, maxDay));
  }

  Future<void> _edit([RecurringExpense? current]) async {
    var name = current?.name ?? '';
    var amount = current == null
        ? ''
        : current.amount.toStringAsFixed(2).replaceAll('.', ',');
    var day = '${current?.dueDay ?? DateTime.now().day}';
    var note = current?.note ?? '';
    var category = current?.category ?? 'Assinaturas';
    var paymentMethod = current?.paymentMethod ?? 'Pix';
    int? creditCardId = current?.creditCardId;
    Uint8List? iconImage = current?.iconImage;
    String? error;
    final saved = await showDialog<RecurringExpense>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: EdgeInsets.fromLTRB(
            18,
            20,
            18,
            20 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Text(
            current == null ? 'Nova mensalidade' : 'Editar mensalidade',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: name,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (value) => setDialogState(() => name = value),
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    hintText: 'Ex: Netflix, academia, escola',
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      _RecurringAvatar(name: name, image: iconImage, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Imagem da mensalidade',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              iconImage == null
                                  ? 'O Fyno usa um ícone automático pelo nome.'
                                  : 'Logo personalizado importado.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Importar imagem ou logo',
                        onPressed: () async {
                          final picked = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 82,
                            maxWidth: 512,
                            maxHeight: 512,
                          );
                          if (picked == null) return;
                          final bytes = await picked.readAsBytes();
                          if (bytes.length > 900000) {
                            setDialogState(
                              () => error =
                                  'Escolha uma imagem menor que 900 KB.',
                            );
                            return;
                          }
                          setDialogState(() {
                            iconImage = bytes;
                            error = null;
                          });
                        },
                        icon: const Icon(Icons.add_photo_alternate_rounded),
                      ),
                      if (iconImage != null)
                        IconButton(
                          tooltip: 'Usar ícone automático',
                          onPressed: () =>
                              setDialogState(() => iconImage = null),
                          icon: const Icon(Icons.restart_alt_rounded),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: amount,
                  onChanged: (value) => amount = value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valor mensal (R\$)',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: day,
                  onChanged: (value) => day = value,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dia do vencimento',
                    hintText: '1 a 31',
                  ),
                ),
                const SizedBox(height: 10),
                CategoryPickerField(
                  value: category,
                  items: const [
                    'Assinaturas',
                    'Contas',
                    'Moradia',
                    'Educação',
                    'Saúde',
                    'Lazer',
                    'Outros',
                  ],
                  onChanged: (value) => setDialogState(() => category = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Forma de pagamento',
                    prefixIcon: Icon(Icons.credit_card_rounded),
                  ),
                  items:
                      const [
                            'Pix',
                            'Débito',
                            TxItem.creditPaymentMethod,
                            'Dinheiro',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => paymentMethod = value);
                    }
                  },
                ),
                if (paymentMethod == TxItem.creditPaymentMethod) ...[
                  const SizedBox(height: 6),
                  if (_creditCards.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: creditCardId,
                      decoration: const InputDecoration(
                        labelText: 'Cartão de crédito',
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
                          setDialogState(() => creditCardId = value),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Ao marcar como paga, ela entra na categoria acima e compõe a fatura do cartão.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: note,
                  onChanged: (value) => note = value,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final parsedAmount =
                    double.tryParse(
                      amount.replaceAll('.', '').replaceAll(',', '.'),
                    ) ??
                    0;
                final parsedDay = int.tryParse(day) ?? 0;
                if (name.trim().isEmpty ||
                    parsedAmount <= 0 ||
                    parsedDay < 1 ||
                    parsedDay > 31 ||
                    (paymentMethod == TxItem.creditPaymentMethod &&
                        creditCardId == null)) {
                  setDialogState(
                    () => error =
                        'Informe nome, valor e vencimento válido (1 a 31).',
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  RecurringExpense(
                    id: current?.id,
                    name: name.trim(),
                    amount: parsedAmount,
                    category: category,
                    dueDay: parsedDay,
                    note: note.trim().isEmpty ? null : note.trim(),
                    iconImage: iconImage,
                    paymentMethod: paymentMethod,
                    creditCardId: creditCardId,
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await _repository.save(saved);
    await _load();
  }

  Future<void> _markPaid(RecurringExpense item) async {
    await _repository.markPaid(item, DateTime.now());
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.paymentMethod == TxItem.creditPaymentMethod
                ? 'Mensalidade adicionada à fatura do cartão.'
                : 'Pagamento registrado nas despesas deste mês.',
          ),
        ),
      );
    }
  }

  Future<void> _archive(RecurringExpense item) async {
    if (item.id == null) return;
    await _repository.archive(item.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final monthly = _items.fold<double>(0, (sum, item) => sum + item.amount);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Assinaturas e mensalidades')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Adicionar'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Compromisso fixo',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${FormatBR.money(monthly)} por mês',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${FormatBR.money(monthly * 12)} projetados por ano • ${_items.length} serviço(s)',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Icon(Icons.subscriptions_rounded, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'Cadastre assinaturas, escola, academia, aluguel e outras despesas mensais.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ..._items.map((item) {
                    final paid = item.id != null && _paidIds.contains(item.id);
                    final due = _dueDate(item);
                    final overdue =
                        !paid &&
                        due.isBefore(DateTime(now.year, now.month, now.day));
                    final status = paid
                        ? 'Pago neste mês'
                        : overdue
                        ? 'Atrasado'
                        : 'Vence dia ${item.dueDay}';
                    final color = paid
                        ? Colors.green
                        : overdue
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary;
                    return Card(
                      elevation: 0,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
                        leading: _RecurringAvatar(
                          name: item.name,
                          image: item.iconImage,
                          paid: paid,
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${item.category} • ${item.paymentMethod} • $status',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              FormatBR.money(item.amount),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'paid') _markPaid(item);
                                if (value == 'edit') _edit(item);
                                if (value == 'archive') _archive(item);
                              },
                              itemBuilder: (_) => [
                                if (!paid)
                                  const PopupMenuItem(
                                    value: 'paid',
                                    child: Text('Marcar como pago'),
                                  ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                const PopupMenuItem(
                                  value: 'archive',
                                  child: Text('Encerrar mensalidade'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _RecurringAvatar extends StatelessWidget {
  const _RecurringAvatar({
    required this.name,
    this.image,
    this.paid = false,
    this.size = 44,
  });

  final String name;
  final Uint8List? image;
  final bool paid;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = recurringBrandVisual(name);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: brand.color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(size * .3),
          ),
          clipBehavior: Clip.antiAlias,
          child: image == null
              ? Icon(brand.icon, color: brand.color, size: size * .58)
              : Image.memory(image!, fit: BoxFit.cover, gaplessPlayback: true),
        ),
        if (paid)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}
