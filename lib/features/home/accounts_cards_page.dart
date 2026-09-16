import 'package:flutter/material.dart';

import '../../shared/format/format_br.dart';
import 'accounts_cards_repository.dart';
import 'add_transaction_page.dart';
import 'models/tx_type.dart';

class AccountsCardsPage extends StatefulWidget {
  const AccountsCardsPage({super.key});

  @override
  State<AccountsCardsPage> createState() => _AccountsCardsPageState();
}

class _AccountsCardsPageState extends State<AccountsCardsPage> {
  final _repository = AccountsCardsRepository();
  bool _loading = true;
  List<FinancialAccount> _accounts = const [];
  List<CardSummary> _cards = const [];
  Map<int, double> _accountBalances = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _repository.getAccounts(),
      _repository.getCardSummaries(),
    ]);
    final accounts = results[0] as List<FinancialAccount>;
    final balances = await Future.wait(
      accounts.map(_repository.getAccountBalance),
    );
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _cards = results[1] as List<CardSummary>;
      _accountBalances = {
        for (var i = 0; i < accounts.length; i++)
          if (accounts[i].id != null) accounts[i].id!: balances[i],
      };
      _loading = false;
    });
  }

  double _moneyValue(String value) =>
      double.tryParse(value.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  Future<void> _addAccount() async {
    var name = '';
    var type = 'Conta corrente';
    var balance = '';
    String? error;
    final result = await showDialog<FinancialAccount>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nova conta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Nome da conta'),
                  onChanged: (value) => name = value,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items:
                      const [
                            'Conta corrente',
                            'Conta digital',
                            'Poupança',
                            'Dinheiro',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => type = value ?? type,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Saldo inicial (R\$)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (value) => balance = value,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
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
                if (name.trim().isEmpty) {
                  setLocal(() => error = 'Informe o nome da conta.');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  FinancialAccount(
                    name: name.trim(),
                    type: type,
                    initialBalance: _moneyValue(balance),
                    colorValue: 0xFF167D64,
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _repository.saveAccount(result);
    await _load();
  }

  Future<void> _addCard() async {
    var name = '';
    var brand = 'Mastercard';
    var lastFour = '';
    var limit = '';
    var closingDay = '20';
    var dueDay = '28';
    int? accountId = _accounts.isEmpty ? null : _accounts.first.id;
    String? error;
    final result = await showDialog<CreditCardItem>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Novo cartão'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Nome do cartão',
                  ),
                  onChanged: (v) => name = v,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: brand,
                  decoration: const InputDecoration(labelText: 'Bandeira'),
                  items:
                      const [
                            'Mastercard',
                            'Visa',
                            'Elo',
                            'American Express',
                            'Outra',
                          ]
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => brand = v ?? brand,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Últimos 4 dígitos (opcional)',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onChanged: (v) => lastFour = v,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Limite (R\$)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) => limit = v,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: closingDay,
                        decoration: const InputDecoration(
                          labelText: 'Fecha dia',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => closingDay = v,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        initialValue: dueDay,
                        decoration: const InputDecoration(
                          labelText: 'Vence dia',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => dueDay = v,
                      ),
                    ),
                  ],
                ),
                if (_accounts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: accountId,
                    decoration: const InputDecoration(
                      labelText: 'Conta de pagamento',
                    ),
                    items: _accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => accountId = v,
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
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
                final parsedLimit = _moneyValue(limit);
                final close = int.tryParse(closingDay) ?? 0;
                final due = int.tryParse(dueDay) ?? 0;
                if (name.trim().isEmpty ||
                    parsedLimit <= 0 ||
                    close < 1 ||
                    close > 31 ||
                    due < 1 ||
                    due > 31 ||
                    (lastFour.isNotEmpty && lastFour.length != 4)) {
                  setLocal(
                    () => error =
                        'Revise nome, limite, datas e os últimos 4 dígitos.',
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  CreditCardItem(
                    name: name.trim(),
                    brand: brand,
                    lastFour: lastFour.isEmpty ? null : lastFour,
                    limitAmount: parsedLimit,
                    closingDay: close,
                    dueDay: due,
                    accountId: accountId,
                    colorValue: 0xFF123F36,
                  ),
                );
              },
              child: const Text('Salvar cartão'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _repository.saveCard(result);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final used = _cards.fold<double>(0, (sum, item) => sum + item.outstanding);
    final available = _cards.fold<double>(
      0,
      (sum, item) => sum + item.available,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Contas e cartões')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Visão consolidada',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          FormatBR.money(used),
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'em aberto nos cartões',
                          style: TextStyle(
                            color: cs.onPrimary.withValues(alpha: .82),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${FormatBR.money(available)} de limite disponível',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(
                    title: 'Cartões',
                    action: 'Adicionar cartão',
                    onTap: _addCard,
                  ),
                  const SizedBox(height: 10),
                  if (_cards.isEmpty)
                    _EmptyCard(
                      text:
                          'Cadastre seu primeiro cartão para organizar compras e faturas.',
                    )
                  else
                    ..._cards.map(
                      (summary) => _CreditCardTile(
                        summary: summary,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CardInvoicePage(card: summary.card),
                            ),
                          );
                          await _load();
                        },
                      ),
                    ),
                  const SizedBox(height: 22),
                  _SectionTitle(
                    title: 'Contas',
                    action: 'Adicionar conta',
                    onTap: _addAccount,
                  ),
                  const SizedBox(height: 10),
                  if (_accounts.isEmpty)
                    _EmptyCard(
                      text:
                          'Adicione uma conta corrente, digital, poupança ou dinheiro.',
                    )
                  else
                    ..._accounts.map(
                      (account) => Card(
                        elevation: 0,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
                            ),
                          ),
                          title: Text(
                            account.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(account.type),
                          trailing: Text(
                            FormatBR.money(
                              _accountBalances[account.id] ??
                                  account.initialBalance,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onTap,
  });
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
      TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded),
        label: Text(action),
      ),
    ],
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _CreditCardTile extends StatelessWidget {
  const _CreditCardTile({required this.summary, required this.onTap});
  final CardSummary summary;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = summary.card.limitAmount <= 0
        ? 0.0
        : summary.outstanding / summary.card.limitAmount;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: const Icon(Icons.credit_card_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.card.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${summary.card.brand} • fecha dia ${summary.card.closingDay} • vence dia ${summary.card.dueDay}',
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${FormatBR.money(summary.outstanding)} em aberto',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0).toDouble(),
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 7),
              Text(
                '${FormatBR.money(summary.available)} disponível de ${FormatBR.money(summary.card.limitAmount)}',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CardInvoicePage extends StatefulWidget {
  const CardInvoicePage({super.key, required this.card});
  final CreditCardItem card;
  @override
  State<CardInvoicePage> createState() => _CardInvoicePageState();
}

class _CardInvoicePageState extends State<CardInvoicePage> {
  final _repository = AccountsCardsRepository();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  CardInvoice? _invoice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final invoice = await _repository.getInvoice(widget.card, _month);
    if (mounted) setState(() => _invoice = invoice);
  }

  Future<void> _pay() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionPage(
          type: TxType.expense,
          prefillTitle: 'Pagamento ${widget.card.name}',
          prefillAmount: _invoice?.remaining,
          prefillCategory: 'Cartão de crédito',
          prefillPaymentMethod: 'Pagamento da fatura',
          prefillCreditCardId: widget.card.id,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    return Scaffold(
      appBar: AppBar(title: Text(widget.card.displayName)),
      body: invoice == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(
                          () =>
                              _month = DateTime(_month.year, _month.month - 1),
                        );
                        _load();
                      },
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        FormatBR.monthYear(_month),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(
                          () =>
                              _month = DateTime(_month.year, _month.month + 1),
                        );
                        _load();
                      },
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fatura restante',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          FormatBR.money(invoice.remaining),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Compras ${FormatBR.money(invoice.purchaseTotal)} • pagamentos ${FormatBR.money(invoice.paymentTotal)}',
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: invoice.remaining > 0 ? _pay : null,
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                            ),
                            label: const Text('Registrar pagamento'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Compras da fatura',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (invoice.purchases.isEmpty)
                  const _EmptyCard(text: 'Nenhuma compra nesta fatura.'),
                ...invoice.purchases.map(
                  (tx) => ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.shopping_bag_outlined),
                    ),
                    title: Text(
                      tx.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${tx.category} • ${FormatBR.date(tx.date)}',
                    ),
                    trailing: Text(
                      FormatBR.money(tx.amount),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                if (invoice.payments.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Pagamentos',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  ...invoice.payments.map(
                    (tx) => ListTile(
                      leading: const Icon(Icons.check_circle_rounded),
                      title: Text(tx.title),
                      trailing: Text('- ${FormatBR.money(tx.amount)}'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
