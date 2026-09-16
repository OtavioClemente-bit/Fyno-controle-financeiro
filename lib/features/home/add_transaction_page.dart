import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:controle_financeiro/core/db/app_db.dart';

import 'package:controle_financeiro/shared/format/format_br.dart';
import 'package:controle_financeiro/shared/input_formatters/currency_ptbr_input_formatter.dart';
import 'package:controle_financeiro/shared/widgets/adaptive_pair.dart';

import 'models/tx_item.dart';
import 'models/tx_type.dart';
import 'models/vehicle.dart';
import 'models/fuel_log.dart';
import 'repositories/vehicle_repository.dart';
import 'repositories/fuel_log_repository.dart';

import 'confirm_receipt_items_page.dart';
import 'receipt_ocr_service.dart';
import 'receipt_qr_service.dart';
import 'receipt_qr_scanner_page.dart';
import 'receipt_qr_portal_page.dart';
import 'receipt_item_draft.dart';
import 'receipt_items_repository.dart';
import 'receipt_image_store.dart';
import 'accounts_cards_repository.dart';

class _CatOption {
  final int id;
  final String name;
  final String? iconKey;

  const _CatOption({
    required this.id,
    required this.name,
    required this.iconKey,
  });
}

enum _ReceiptItemsSource { qr, image }

class AddTransactionPage extends StatefulWidget {
  final TxType type;

  // Prefill (usado pela importação de notificações)
  final String? prefillTitle;
  final String? prefillNote;
  final double? prefillAmount;
  final int? prefillDateMs;
  final String? prefillPaymentMethod;
  final String? prefillCategory;
  final int? prefillCreditCardId;
  final ValueChanged<TxItem>? onSaved;

  const AddTransactionPage({
    super.key,
    required this.type,
    this.prefillTitle,
    this.prefillNote,
    this.prefillAmount,
    this.prefillDateMs,
    this.prefillPaymentMethod,
    this.prefillCategory,
    this.prefillCreditCardId,
    this.onSaved,
  });

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final AccountsCardsRepository _accountsCardsRepository =
      AccountsCardsRepository();
  List<CreditCardItem> _creditCards = const [];
  List<FinancialAccount> _accounts = const [];
  int? _creditCardId;
  int? _accountId;
  // ===== Combustível (modo especial quando categoria == 'Combustível' e for Despesa) =====
  final VehicleRepository _vehicleRepo = VehicleRepository();
  final FuelLogRepository _fuelRepo = FuelLogRepository();
  List<Vehicle> _vehicles = const <Vehicle>[];
  int? _fuelVehicleId; // null = sem veículo / não vincular
  final _fuelOdoCtrl = TextEditingController();
  final _fuelLitersCtrl = TextEditingController();
  final _fuelPriceCtrl = TextEditingController();

  // ===== Investimento (modo especial quando categoria == 'Investimento' e for Despesa) =====
  static const List<String> _investmentKinds = <String>[
    'Ações',
    'FIIs',
    'Tesouro Selic',
    'Tesouro IPCA+',
    'Tesouro Prefixado',
    'CDB/LCI/LCA',
    'Fundo',
    'Cripto',
    'Previdência',
    'Outros',
  ];

  String _investmentKind = 'Ações';
  final _invAssetCtrl = TextEditingController(); // ex: PETR4, HGLG11, etc
  final _invQtyCtrl = TextEditingController(); // opcional
  final _invBrokerCtrl = TextEditingController(); // opcional (banco/corretora)

  bool get _isInvestmentIncome {
    if (!_isIncome) return false;
    final c = _normCat(_category);
    final s = _normCat(_incomeSource);
    return c == 'investimento' ||
        c == 'investimentos' ||
        c == 'rendimentos' ||
        s == 'rendimentos';
  }

  bool get _isFuelExpense => !_isIncome && _category == 'Combustível';
  Vehicle? get _selectedVehicle {
    if (_fuelVehicleId == null) return null;
    for (final v in _vehicles) {
      if (v.id == _fuelVehicleId) return v;
    }
    return null;
  }

  double? _parseNumFlexible(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.')) ??
        double.tryParse(t.replaceAll(',', '.'));
  }

  Future<void> _loadVehicles() async {
    try {
      final dynRepo = _vehicleRepo as dynamic;
      final candidates = <Future<List<dynamic>> Function()>[
        () async => await dynRepo.getAll(),
        () async => await dynRepo.getAllVehicles(),
        () async => await dynRepo.listAll(),
        () async => await dynRepo.getVehicles(),
        () async => await dynRepo.fetchAll(),
      ];
      for (final fn in candidates) {
        try {
          final res = await fn();
          final list = res.cast<dynamic>();
          final vehicles = list.map((e) => e as Vehicle).toList();
          if (!mounted) return;
          setState(() => _vehicles = vehicles);
          return;
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _vehicles = const <Vehicle>[]);
  }

  final _titleCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  String _category = 'Mercado';
  String? _imagePath;

  // ===== Digitalização de comprovante (itens) =====
  bool _isReceiptWithItems = false;
  bool _isExtractingReceipt = false;
  List<ReceiptItemDraft> _receiptItemsDraft = const <ReceiptItemDraft>[];
  _ReceiptItemsSource? _receiptItemsSource;

  // ✅ PASSO 1 — novos campos (UI)
  String _paymentMethod = 'Pix'; // só para DESPESA
  String _incomeSource = 'Salário'; // só para RECEITA

  static const List<String> _paymentMethods = [
    'Pix',
    'Débito',
    TxItem.creditPaymentMethod,
    'Dinheiro',
    TxItem.creditCardBillPaymentMethod,
  ];

  static const List<String> _incomeSources = [
    'Salário',
    'Rendimentos',
    'Extra',
    'Presente',
    'Outros',
  ];

  // Snapshot inicial (para detectar alterações não salvas)
  late final DateTime _initialDate;
  late final String _initialCategory;
  late final String? _initialImagePath;

  late final String _initialPaymentMethod;
  late final String _initialIncomeSource;

  bool _isSaving = false;
  bool _handlingBack = false; // ✅ trava reentrância (evita !debugLocked)
  bool _allowPop = false; // ✅ libera o pop quando CONFIRMAR sair / salvar

  final ImagePicker _picker = ImagePicker();

  bool get _isIncome => widget.type == TxType.income;

  @override
  void initState() {
    super.initState();
    _applyPrefill();
    _loadCategories();
    _loadCreditCards();
    _initialDate = _date;
    _initialCategory = _category;
    _initialImagePath = _imagePath;

    _initialPaymentMethod = _paymentMethod;
    _initialIncomeSource = _incomeSource;

    _titleCtrl.addListener(_refresh);
    _valueCtrl.addListener(_refresh);
    _noteCtrl.addListener(_refresh);
    // combustível
    _loadVehicles();
    _fuelOdoCtrl.addListener(_refresh);
    _fuelLitersCtrl.addListener(_refresh);
    _fuelPriceCtrl.addListener(_refresh);

    // investimento
    _invAssetCtrl.addListener(_refresh);
    _invQtyCtrl.addListener(_refresh);
    _invBrokerCtrl.addListener(_refresh);
  }

  void _applyPrefill() {
    _creditCardId = widget.prefillCreditCardId;
    final t = widget.prefillTitle;
    if (t != null && t.trim().isNotEmpty) {
      _titleCtrl.text = t.trim();
    }

    final note = widget.prefillNote;
    if (note != null && note.trim().isNotEmpty) {
      _noteCtrl.text = note.trim();
    }

    final a = widget.prefillAmount;
    if (a != null) {
      _valueCtrl.text = _doubleToPtbr(a);
    }

    final ms = widget.prefillDateMs;
    if (ms != null) {
      _date = DateTime.fromMillisecondsSinceEpoch(ms);
    }

    final method = widget.prefillPaymentMethod?.trim();
    if (method != null && _paymentMethods.contains(method)) {
      _paymentMethod = method;
    }

    final category = widget.prefillCategory?.trim();
    if (category != null && category.isNotEmpty) {
      _category = category;
    }
  }

  Future<void> _loadCreditCards() async {
    final results = await Future.wait([
      _accountsCardsRepository.getCards(),
      _accountsCardsRepository.getAccounts(),
    ]);
    final cards = results[0] as List<CreditCardItem>;
    final accounts = results[1] as List<FinancialAccount>;
    if (!mounted) return;
    setState(() {
      _creditCards = cards;
      _accounts = accounts;
      if (_creditCardId != null &&
          !cards.any((card) => card.id == _creditCardId)) {
        _creditCardId = null;
      }
      if (_accountId == null && _creditCardId != null) {
        final selected = cards.where((card) => card.id == _creditCardId);
        if (selected.isNotEmpty) _accountId = selected.first.accountId;
      }
    });
  }

  String _doubleToPtbr(double v) {
    // Mantém 2 casas e troca ponto por vírgula (0.00 -> 0,00).
    final s = v.abs().toStringAsFixed(2).replaceAll('.', ',');
    return v < 0 ? '-$s' : s;
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
    _fuelOdoCtrl.removeListener(_refresh);
    _invAssetCtrl.removeListener(_refresh);
    _invQtyCtrl.removeListener(_refresh);
    _invBrokerCtrl.removeListener(_refresh);
    // _fuelLitersCtrl e _fuelPriceCtrl têm listeners inline; apenas dispose é suficiente

    _fuelOdoCtrl.dispose();
    _fuelLitersCtrl.dispose();
    _fuelPriceCtrl.dispose();

    _invAssetCtrl.dispose();
    _invQtyCtrl.dispose();
    _invBrokerCtrl.dispose();

    _titleCtrl.dispose();
    _valueCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _sanitizeFuelVehicleValue() {
    if (_vehicles.isEmpty) return;
    final ids = <int>{};
    for (final v in _vehicles) {
      final id = v.id;
      if (id is int) ids.add(id);
    }
    if (_fuelVehicleId != null && !ids.contains(_fuelVehicleId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _fuelVehicleId = null);
      });
    }
  }

  // ---------- UX helpers
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  double? _parsePtBrMoney(String text) {
    var t = text.trim();
    if (t.isEmpty) return null;

    // remove prefixos comuns
    t = t.replaceAll('R\$', '').replaceAll(' ', '').trim();

    // Se veio apenas dígitos (CurrencyPtBrInputFormatter costuma guardar assim),
    // interpretamos como centavos.
    final onlyDigits = t.replaceAll(RegExp(r'[^0-9]'), '');
    final hasSep = t.contains(',') || t.contains('.');
    if (!hasSep && onlyDigits.isNotEmpty) {
      final cents = double.tryParse(onlyDigits);
      if (cents == null) return null;
      return cents / 100.0;
    }

    // pt-BR: remove milhar '.' e troca ',' por '.'
    final cleaned = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleaned);
  }

  bool get _hasChanges {
    return _titleCtrl.text.trim().isNotEmpty ||
        _valueCtrl.text.trim().isNotEmpty ||
        _noteCtrl.text.trim().isNotEmpty ||
        _date != _initialDate ||
        _category != _initialCategory ||
        _imagePath != _initialImagePath ||
        _receiptItemsDraft.isNotEmpty ||
        _paymentMethod != _initialPaymentMethod ||
        _incomeSource != _initialIncomeSource;
  }

  bool get _canSave {
    if (_isSaving) return false;
    final title = _titleCtrl.text.trim();
    final amount = _parsePtBrMoney(_valueCtrl.text);

    if (_isFuelExpense && _fuelVehicleId != null) {
      final odo = _parseNumFlexible(_fuelOdoCtrl.text);
      final liters = _parseNumFlexible(_fuelLitersCtrl.text);
      final price = _parsePtBrMoney(_fuelPriceCtrl.text);
      final okFuel =
          odo != null &&
          odo > 0 &&
          liters != null &&
          liters > 0 &&
          price != null &&
          price > 0;
      // título pode ser vazio: será preenchido automaticamente
      return okFuel && amount != null && amount > 0;
    }

    final needsCard =
        !_isIncome &&
        (_paymentMethod == TxItem.creditPaymentMethod ||
            _paymentMethod == TxItem.creditCardBillPaymentMethod);
    return title.isNotEmpty &&
        amount != null &&
        amount > 0 &&
        (!needsCard || _creditCardId != null);
  }

  // ---------- Categories (DB) ----------
  // The app stores categories in SQLite (table: categories) with an `icon_key`.
  // We load them dynamically so new categories appear immediately here.
  List<_CatOption> _catOptions = [];
  bool _catsLoading = true;

  // Fallback list (used only if DB is empty / not migrated yet)
  static const List<_CatOption> _fallbackExpenseCategories = <_CatOption>[
    _CatOption(id: 0, name: 'Mercado', iconKey: 'market'),
    _CatOption(id: 0, name: 'Alimentação', iconKey: 'restaurant'),
    _CatOption(id: 0, name: 'Combustível', iconKey: 'fuel'),
    _CatOption(id: 0, name: 'Investimento', iconKey: 'invest'),
    _CatOption(id: 0, name: 'Contas', iconKey: 'bill'),
    _CatOption(id: 0, name: 'Casa', iconKey: 'home'),
    _CatOption(id: 0, name: 'Transporte', iconKey: 'transport'),
    _CatOption(id: 0, name: 'Lazer', iconKey: 'fun'),
    _CatOption(id: 0, name: 'Saúde', iconKey: 'health'),
    _CatOption(id: 0, name: 'Educação', iconKey: 'edu'),
    _CatOption(id: 0, name: 'Viagem', iconKey: 'travel'),
    _CatOption(id: 0, name: 'Outros', iconKey: 'other'),
  ];

  static const List<_CatOption> _fallbackIncomeCategories = <_CatOption>[
    _CatOption(id: 0, name: 'Salário', iconKey: 'salary'),
    _CatOption(id: 0, name: 'Rendimentos', iconKey: 'invest'),
    _CatOption(id: 0, name: 'Vendas', iconKey: 'cart'),
    _CatOption(id: 0, name: 'Freelance', iconKey: 'work'),
    _CatOption(id: 0, name: 'Outros', iconKey: 'other'),
  ];

  String _normCat(String s) => s.trim().toLowerCase();

  List<_CatOption> _mergeFallbackWithDb(List<_CatOption> dbOpts) {
    final dbByKey = <String, _CatOption>{
      for (final o in dbOpts) _normCat(o.name): o,
    };

    final used = <String>{};
    final merged = <_CatOption>[];

    // 1) Sempre mostrar as categorias "do sistema" (fallback)
    final fallback = _isIncome
        ? _fallbackIncomeCategories
        : _fallbackExpenseCategories;
    for (final f in fallback) {
      final key = _normCat(f.name);
      final db = dbByKey[key];
      if (db != null) {
        merged.add(
          _CatOption(
            id: db.id,
            name: db.name,
            iconKey: db.iconKey ?? f.iconKey,
          ),
        );
      } else {
        merged.add(f);
      }
      used.add(key);
    }

    // 2) Acrescentar categorias do usuário/DB que não existam no fallback
    for (final o in dbOpts) {
      final key = _normCat(o.name);
      if (key.isEmpty || used.contains(key)) continue;
      merged.add(o);
      used.add(key);
    }

    return merged;
  }

  static const Map<String, IconData> _iconByKey = {
    // finance
    'wallet': Icons.account_balance_wallet_rounded,
    'salary': Icons.payments_rounded,
    'card': Icons.credit_card_rounded,
    'bank': Icons.account_balance_rounded,
    // life
    'home': Icons.home_rounded,
    'market': Icons.local_grocery_store_rounded,
    'health': Icons.health_and_safety_rounded,
    'gym': Icons.fitness_center_rounded,
    'transport': Icons.directions_car_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'travel': Icons.flight_takeoff_rounded,
    'gift': Icons.card_giftcard_rounded,
    'education': Icons.school_rounded,
    'pets': Icons.pets_rounded,
    'restaurant': Icons.restaurant_rounded,
    'coffee': Icons.coffee_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'movie': Icons.movie_rounded,
    'work': Icons.work_rounded,
    'invest': Icons.trending_up_rounded,
    'bill': Icons.receipt_long_rounded,
    'fun': Icons.celebration_rounded,
    'edu': Icons.school_rounded,
    'cart': Icons.shopping_cart_rounded,
    'other': Icons.category_rounded,
  };

  IconData _iconForKey(String? key) {
    if (key == null) return Icons.category_rounded;
    return _iconByKey[key] ?? Icons.category_rounded;
  }

  bool _isAssetIconKey(String key) {
    final k = key.trim();
    if (k.isEmpty) return false;
    if (k.startsWith('assets/')) return true;
    return RegExp(
      r'\.(png|jpg|jpeg|webp|gif)$',
      caseSensitive: false,
    ).hasMatch(k);
  }

  Widget _catIconWidget(String iconKey, Color color, {double size = 18}) {
    final k = iconKey.trim();
    if (_isAssetIconKey(k)) {
      return Image.asset(k, width: size, height: size, fit: BoxFit.contain);
    }
    return Icon(_iconForKey(k), color: color, size: size);
  }

  Future<void> _loadCategories({bool keepSelected = true}) async {
    try {
      final db = await AppDb.instance;
      final rows = await db.query(
        'categories',
        columns: ['id', 'name', 'icon_key'],
        orderBy: 'name COLLATE NOCASE ASC',
      );

      final opts = rows
          .map(
            (r) => _CatOption(
              id: (r['id'] as int?) ?? 0,
              name: (r['name'] as String?)?.trim() ?? '',
              iconKey: (r['icon_key'] as String?)?.trim(),
            ),
          )
          .where((o) => o.name.isNotEmpty)
          .toList();

      final hasDbCats = opts.isNotEmpty;
      final merged = _mergeFallbackWithDb(opts);

      if (!mounted) return;
      setState(() {
        _catOptions = merged;
        _catsLoading = false;
      });

      // Ensure selected category exists
      final availableNames = merged.map((e) => e.name).toSet();
      if (!hasDbCats) {
        // Sem categorias no DB → mantém só as do sistema (fallback)
        if (!keepSelected && mounted) {
          setState(
            () => _category = (_isIncome
                ? _fallbackIncomeCategories.first.name
                : _fallbackExpenseCategories.first.name),
          );
        }
        return;
      }

      if (!availableNames.contains(_category)) {
        setState(() => _category = merged.first.name);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _catsLoading = false;
        _catOptions = [];
      });
    }
  }

  Future<void> _openCategoryPicker() async {
    if (_catsLoading) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final txt = TextEditingController();
        List<_CatOption> filtered = List.of(_catOptions);

        void applyFilter(String q) {
          final s = q.trim().toLowerCase();
          if (s.isEmpty) {
            filtered = List.of(_catOptions);
          } else {
            filtered = _catOptions
                .where((c) => c.name.toLowerCase().contains(s))
                .toList();
          }
        }

        return StatefulBuilder(
          builder: (ctx, setSB) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 14,
                  right: 14,
                  top: 6,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: txt,
                            onChanged: (v) => setSB(() => applyFilter(v)),
                            decoration: InputDecoration(
                              hintText: 'Buscar categoria…',
                              prefixIcon: const Icon(Icons.search_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _showAddCategoryDialog();
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Nova'),
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.isEmpty ? 1 : filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          if (filtered.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Nenhuma categoria encontrada.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            );
                          }
                          final c = filtered[i];
                          final selected = c.name == _category;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cs.primary.withValues(
                                alpha: 0.10,
                              ),
                              child: Icon(
                                _iconForKey(c.iconKey),
                                color: cs.primary,
                              ),
                            ),
                            title: Text(c.name),
                            trailing: selected
                                ? Icon(Icons.check_rounded, color: cs.primary)
                                : null,
                            onTap: () {
                              if (!mounted) return;
                              setState(() => _category = c.name);
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddCategoryDialog() async {
    final cs = Theme.of(context).colorScheme;
    final nameCtrl = TextEditingController();
    String iconKey = 'other';

    final iconEntries = _iconByKey.entries.toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Nova categoria'),
          content: StatefulBuilder(
            builder: (ctx, setSB) {
              return SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Ícone',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 210,
                      child: GridView.builder(
                        itemCount: iconEntries.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                        itemBuilder: (ctx, i) {
                          final e = iconEntries[i];
                          final selected = e.key == iconKey;
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setSB(() => iconKey = e.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? cs.primary
                                      : cs.outlineVariant,
                                ),
                                color: selected
                                    ? cs.primary.withValues(alpha: 0.12)
                                    : cs.surface,
                              ),
                              child: Icon(
                                e.value,
                                color: selected ? cs.primary : cs.onSurface,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;

                try {
                  final db = await AppDb.instance;
                  await db.insert('categories', {
                    'name': name,
                    'icon_key': iconKey,
                    'created_at_ms': DateTime.now().millisecondsSinceEpoch,
                  }, conflictAlgorithm: ConflictAlgorithm.ignore);
                } catch (_) {}

                if (!mounted || !ctx.mounted) return;
                Navigator.of(ctx).pop();
                await _loadCategories(keepSelected: false);
                if (mounted) {
                  // Select the newly created category if it exists
                  final match = _catOptions
                      .where((c) => c.name.toLowerCase() == name.toLowerCase())
                      .toList();
                  if (match.isNotEmpty) {
                    setState(() => _category = match.first.name);
                  }
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryField() {
    final cs = Theme.of(context).colorScheme;

    final hasDbCats = _catOptions.isNotEmpty;
    final iconKey = hasDbCats
        ? _catOptions
                  .firstWhere(
                    (c) => c.name == _category,
                    orElse: () => _catOptions.first,
                  )
                  .iconKey ??
              'category'
        : 'category';

    final label = _catsLoading ? 'Carregando…' : _category;

    return InkWell(
      onTap: _catsLoading ? null : _openCategoryPicker,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primary.withValues(alpha: 0.10),
              child: _catIconWidget(iconKey, cs.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: cs.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI styling
  InputDecoration _inputDeco({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 1.8),
      ),
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  // Alias para manter compatibilidade com trechos que usam inputDeco(...)
  // (alguns pontos do arquivo chamavam sem o underscore).
  InputDecoration inputDeco({
    required String label,
    String? hint,
    required IconData icon,
  }) => _inputDeco(label: label, hint: hint, icon: icon);

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
      ),
    );
  }

  Widget _card({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: cs.shadow.withValues(alpha: .06),
          ),
        ],
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
      ),
      child: child,
    );
  }

  // ---------- Actions
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
    final xfile = await _picker.pickImage(source: source, imageQuality: 100);
    if (xfile != null && mounted) {
      setState(() {
        _imagePath = xfile.path;
        if (_receiptItemsSource == _ReceiptItemsSource.image) {
          _isReceiptWithItems = false;
          _receiptItemsDraft = const <ReceiptItemDraft>[];
          _receiptItemsSource = null;
        }
      });
    }
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
      setState(() {
        _imagePath = null;
        if (_receiptItemsSource == _ReceiptItemsSource.image) {
          _isReceiptWithItems = false;
          _receiptItemsDraft = const <ReceiptItemDraft>[];
          _receiptItemsSource = null;
        }
      });
    }
  }

  Future<void> _openImagePreview() async {
    if (_imagePath == null) return;

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: InteractiveViewer(
                maxScale: 4,
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Image.file(File(_imagePath!), fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _extractReceiptItems() async {
    if (_imagePath == null) return;

    setState(() => _isExtractingReceipt = true);
    try {
      final itemsQr = await ReceiptQrService.extractItemsViaQr(_imagePath!);
      final items = itemsQr.isNotEmpty
          ? itemsQr
          : await ReceiptOcrService.extractFromImagePath(_imagePath!);
      if (!mounted) return;

      final edited = await Navigator.of(context).push<List<ReceiptItemDraft>>(
        MaterialPageRoute(
          builder: (_) => ConfirmReceiptItemsPage(initialItems: items),
        ),
      );

      if (!mounted) return;
      if (edited != null) {
        setState(() {
          _receiptItemsDraft = edited;
          _isReceiptWithItems = edited.isNotEmpty;
          _receiptItemsSource = edited.isEmpty
              ? null
              : _ReceiptItemsSource.image;
        });
      }
    } catch (_) {
      if (mounted) _toast('Não consegui ler o QR nem digitalizar por OCR');
    } finally {
      if (mounted) setState(() => _isExtractingReceipt = false);
    }
  }

  Future<void> _scanReceiptQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ReceiptQrScannerPage()),
    );
    if (raw == null || !mounted) return;

    setState(() => _isExtractingReceipt = true);
    _toast('QR Code identificado. Consultando o cupom…');
    try {
      final lookup = await ReceiptQrService.lookupItemsFromQrValue(raw);
      if (!mounted) return;

      var items = lookup.items;
      final shouldOpenPortal = switch (lookup.status) {
        ReceiptQrLookupStatus.success => false,
        ReceiptQrLookupStatus.interactiveVerificationRequired => true,
        ReceiptQrLookupStatus.noItems || ReceiptQrLookupStatus.networkError =>
          await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  icon: Icon(
                    lookup.status == ReceiptQrLookupStatus.networkError
                        ? Icons.wifi_off_rounded
                        : Icons.receipt_long_outlined,
                  ),
                  title: Text(
                    lookup.status == ReceiptQrLookupStatus.networkError
                        ? 'Consulta automática indisponível'
                        : 'Portal com formato diferente',
                  ),
                  content: Text(
                    lookup.status == ReceiptQrLookupStatus.networkError
                        ? 'Não consegui consultar a nota diretamente. Você pode abrir o portal oficial e tentar por lá.'
                        : 'A nota abriu, mas os produtos não vieram no formato esperado. Posso abrir o portal oficial para concluir.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Agora não'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Abrir portal'),
                    ),
                  ],
                ),
              ) ??
              false,
        ReceiptQrLookupStatus.invalidQr => false,
      };
      if (!mounted) return;

      if (lookup.status == ReceiptQrLookupStatus.invalidQr) {
        _toast('Este código não é de uma NFC-e oficial.');
        return;
      }

      if (shouldOpenPortal && lookup.uri != null) {
        _toast('Conclua a consulta no portal para importar os produtos.');
        final portalItems = await Navigator.of(context)
            .push<List<ReceiptItemDraft>>(
              MaterialPageRoute(
                builder: (_) => ReceiptQrPortalPage(uri: lookup.uri!),
              ),
            );
        if (!mounted || portalItems == null) return;
        items = portalItems;
      }

      if (items.isEmpty) {
        if (lookup.status == ReceiptQrLookupStatus.success ||
            shouldOpenPortal) {
          _toast('Não encontrei produtos para importar nessa nota.');
        }
        return;
      }

      final edited = await Navigator.of(context).push<List<ReceiptItemDraft>>(
        MaterialPageRoute(
          builder: (_) => ConfirmReceiptItemsPage(initialItems: items),
        ),
      );
      if (!mounted || edited == null) return;
      setState(() {
        _receiptItemsDraft = edited;
        _isReceiptWithItems = edited.isNotEmpty;
        _receiptItemsSource = edited.isEmpty ? null : _ReceiptItemsSource.qr;
      });
    } catch (_) {
      _toast('Não foi possível consultar esse cupom agora.');
    } finally {
      if (mounted) setState(() => _isExtractingReceipt = false);
    }
  }

  Future<void> _reviewReceiptItems() async {
    if (_receiptItemsDraft.isEmpty) return;
    final edited = await Navigator.of(context).push<List<ReceiptItemDraft>>(
      MaterialPageRoute(
        builder: (_) =>
            ConfirmReceiptItemsPage(initialItems: _receiptItemsDraft),
      ),
    );
    if (!mounted || edited == null) return;
    setState(() {
      _receiptItemsDraft = edited;
      if (edited.isEmpty) {
        _isReceiptWithItems = false;
        _receiptItemsSource = null;
      }
    });
  }

  void _clearReceiptItems() {
    setState(() {
      _receiptItemsDraft = const <ReceiptItemDraft>[];
      _isReceiptWithItems = false;
      _receiptItemsSource = null;
    });
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair sem salvar?'),
        content: const Text(
          'Você preencheu informações que ainda não foram salvas. '
          'Se sair agora, você vai perder essas alterações.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _handleBack() async {
    if (_handlingBack) return;
    _handlingBack = true;

    try {
      final canLeave = await _confirmDiscardChanges();
      if (!mounted) return;

      if (canLeave) {
        setState(() => _allowPop = true);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pop(context, false);
        });
      }
    } finally {
      _handlingBack = false;
    }
  }

  String _composeFinalNote() {
    final base = _noteCtrl.text.trim();

    // ✅ por enquanto salvamos em note (passo seguinte: criar colunas no DB)
    final tag = _isIncome
        ? 'Origem: $_incomeSource'
        : 'Pagamento: $_paymentMethod';

    if (base.isEmpty) return tag;
    // evita duplicar se o cara editar e voltar aqui
    if (base.contains(tag)) return base;
    return '$tag\n$base';
  }

  Future<void> _save() async {
    var title = _titleCtrl.text.trim();
    final amountFromField = _parsePtBrMoney(_valueCtrl.text);
    final isFuel = _isFuelExpense && _fuelVehicleId != null;

    // validação
    if (isFuel) {
      final odo = _parseNumFlexible(_fuelOdoCtrl.text);
      final liters = _parseNumFlexible(_fuelLitersCtrl.text);
      final price = _parsePtBrMoney(_fuelPriceCtrl.text);
      if (odo == null || odo <= 0) {
        _toast('Informe o odômetro.');
        return;
      }
      if (liters == null || liters <= 0) {
        _toast('Informe os litros.');
        return;
      }
      if (price == null || price <= 0) {
        _toast('Informe o preço por litro.');
        return;
      }
      if (title.isEmpty) {
        title = 'Abastecimento — ${_selectedVehicle?.name ?? "Veículo"}';
      }
      if (amountFromField == null || amountFromField <= 0) {
        _toast('Informe o valor gasto no campo Valor.');
        return;
      }
    }

    final amount = _parsePtBrMoney(_valueCtrl.text) ?? 0;
    if (amount <= 0) {
      _toast('Informe um valor válido.');
      return;
    }

    setState(() => _isSaving = true);

    // nota padrão (pagamento/origem + observação)
    var note = _composeFinalNote();

    try {
      // ✅ se for combustível e tiver veículo selecionado, salva no extrato de combustível também
      if (isFuel) {
        final vehicleId = _fuelVehicleId!;
        final odo = _parseNumFlexible(_fuelOdoCtrl.text)!;
        final liters = _parseNumFlexible(_fuelLitersCtrl.text)!;
        final price = _parsePtBrMoney(_fuelPriceCtrl.text)!;
        final total = amount;

        FuelLog? prev;
        try {
          prev = await (_fuelRepo as dynamic).getPreviousLog(vehicleId, _date);
        } catch (_) {
          try {
            prev = await (_fuelRepo as dynamic).getLastByVehicle(vehicleId);
          } catch (_) {
            prev = null;
          }
        }

        double? kmPerLiter;
        try {
          if (prev != null) {
            final prevOdo = (prev as dynamic).odometer as double?;
            if (prevOdo != null && odo > prevOdo) {
              final dist = odo - prevOdo;
              kmPerLiter = dist / liters;
            }
          }
        } catch (_) {}

        final log = FuelLog.fromMap({
          'id': null,
          'vehicle_id': vehicleId,
          'date_ms': _date.millisecondsSinceEpoch,
          'odometer': odo,
          'liters': liters,
          'price_per_liter': price,
          'total_amount': total,
          'km_per_liter': kmPerLiter,
          'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        });
        await _fuelRepo.insert(log);

        final details = <String>[
          'Veículo: ${_selectedVehicle?.name ?? "Veículo"}',
          'Odômetro: ${odo.toStringAsFixed(1).replaceAll('.', ',')} km',
          'Litros: ${liters.toStringAsFixed(2).replaceAll('.', ',')} L',
          'Preço/L: R\$ ${price.toStringAsFixed(3).replaceAll('.', ',')}',
          if (kmPerLiter != null)
            'Consumo: ${kmPerLiter.toStringAsFixed(2).replaceAll('.', ',')} km/L',
        ].join(' • ');
        note = '$note\n$details';
      }

      // Investimento: entra no extrato normal. Mais tarde você pode filtrar por categoria.
      if (_isInvestmentIncome) {
        final asset = _invAssetCtrl.text.trim();
        final qty = _invQtyCtrl.text.trim();
        final broker = _invBrokerCtrl.text.trim();

        final parts = <String>['Investimento: $_investmentKind'];
        if (asset.isNotEmpty) parts.add('Ativo: $asset');
        if (qty.isNotEmpty) parts.add('Qtd: $qty');
        if (broker.isNotEmpty) parts.add('Corretora: $broker');

        final details = parts.join(' • ');
        note = note.isEmpty ? details : '$note\n$details';

        if (title.isEmpty) {
          title = 'Investimento — $_investmentKind';
        }
      }

      final storedImagePath = await ReceiptImageStore.persist(_imagePath);
      final tx = TxItem(
        title: title,
        amount: amount,
        isIncome: _isIncome,
        date: _date,
        category: _category,
        note: note,
        receiptImagePath: storedImagePath,
        paymentMethod: _isIncome ? _incomeSource : _paymentMethod,
        creditCardId:
            !_isIncome &&
                (_paymentMethod == TxItem.creditPaymentMethod ||
                    _paymentMethod == TxItem.creditCardBillPaymentMethod)
            ? _creditCardId
            : null,
        accountId: !_isIncome && _paymentMethod == TxItem.creditPaymentMethod
            ? null
            : _accountId,
      );

      final db = await AppDb.instance;
      final txId = await db.insert('transactions', tx.toMap());

      // Se o usuário digitalizou itens do comprovante, salva o histórico (vinculado à transação)
      if (_isReceiptWithItems && _receiptItemsDraft.isNotEmpty) {
        await ReceiptItemsRepository.insertMany(
          txId: txId,
          date: _date,
          items: _receiptItemsDraft,
        );
      }
      if (!mounted) return;

      widget.onSaved?.call(tx.copyWith(id: txId));
      setState(() => _allowPop = true);
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Erro ao salvar');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _sanitizeFuelVehicleValue();
    final titlePage = _isIncome ? 'Nova Receita' : 'Nova Despesa';
    final cs = Theme.of(context).colorScheme;
    final compactAppBar =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.25;

    return PopScope(
      canPop: _allowPop,
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
                  TextButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_isIncome ? Icons.add : Icons.remove),
                    label: const Text('Salvar'),
                  ),
                  const SizedBox(width: 6),
                ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: SizedBox(
              child: ElevatedButton.icon(
                onPressed: _canSave ? _save : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isIncome ? Icons.add : Icons.remove),
                label: Text(
                  _isIncome ? 'Salvar Receita' : 'Salvar Despesa',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('Dados'),
                  TextField(
                    controller: _titleCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: _inputDeco(
                      label: 'Descrição',
                      hint: 'Ex: Almoço, Uber, Salário...',
                      icon: Icons.edit,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _valueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyPtBrInputFormatter(),
                    ],
                    decoration: _inputDeco(
                      label: 'Valor (R\$)',
                      hint: '0,00',
                      icon: Icons.attach_money,
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
                          icon: Icons.calendar_month,
                        ),
                        child: Text(FormatBR.date(_date)),
                      ),
                    ),
                    second: _buildCategoryField(),
                  ),
                ],
              ),
            ),

            // ===== Combustível (somente quando for DESPESA e categoria == Combustível) =====
            if (_isFuelExpense) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Combustível',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int?>(
                        initialValue: _fuelVehicleId,
                        isExpanded: true,
                        decoration: inputDeco(
                          label: 'Veículo (opcional)',
                          icon: Icons.directions_car,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'Sem veículo (só lançar no extrato normal)',
                            ),
                          ),
                          ..._vehicles.map(
                            (v) => DropdownMenuItem<int?>(
                              value: v.id,
                              child: Text(v.name),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (!mounted) return;
                          setState(() {
                            _fuelVehicleId = v;
                            if (v == null) {
                              _fuelOdoCtrl.clear();
                              _fuelLitersCtrl.clear();
                              _fuelPriceCtrl.clear();
                            }
                          });
                        },
                      ),
                      if (_fuelVehicleId != null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _fuelOdoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: inputDeco(
                            label: 'Odômetro (km)',
                            icon: Icons.speed,
                            hint: 'Ex: 12345,6',
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AdaptivePair(
                          first: TextField(
                            controller: _fuelLitersCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: inputDeco(
                              label: 'Litros (L)',
                              icon: Icons.opacity,
                              hint: 'Ex: 35,50',
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                          ),
                          second: TextField(
                            controller: _fuelPriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: inputDeco(
                              label: 'Preço/L (R\$)',
                              icon: Icons.local_gas_station,
                              hint: 'Ex: 5,799',
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              CurrencyPtBrInputFormatter(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ✅ PASSO 1 — forma de pagamento (despesa) / origem (receita)
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(
                    _isIncome ? 'Origem da receita' : 'Forma de pagamento',
                  ),
                  // Dedup + safe initialValue para evitar o crash:
                  // "There should be exactly one item with [DropdownButton]'s value".
                  Builder(
                    builder: (_) {
                      final list =
                          (_isIncome ? _incomeSources : _paymentMethods)
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();
                      final unique = <String>[];
                      final seen = <String>{};
                      for (final v in list) {
                        if (seen.add(v)) unique.add(v);
                      }

                      final current = _isIncome
                          ? _incomeSource
                          : _paymentMethod;
                      final safe = unique.contains(current)
                          ? current
                          : (unique.isEmpty ? null : unique.first);

                      return DropdownButtonFormField<String>(
                        initialValue: safe,
                        isExpanded: true,
                        decoration: _inputDeco(
                          label: _isIncome ? 'Origem' : 'Pagamento',
                          icon: _isIncome ? Icons.payments : Icons.credit_card,
                        ),
                        items: unique
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null || !mounted) return;
                          setState(() {
                            if (_isIncome) {
                              _incomeSource = v;
                            } else {
                              _paymentMethod = v;
                            }
                          });
                        },
                      );
                    },
                  ),
                  if (!_isIncome &&
                      (_paymentMethod == TxItem.creditPaymentMethod ||
                          _paymentMethod ==
                              TxItem.creditCardBillPaymentMethod)) ...[
                    const SizedBox(height: 10),
                    if (_creditCards.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Cadastre um cartão na Central de Contas e Cartões antes de salvar.',
                          style: TextStyle(color: cs.onErrorContainer),
                        ),
                      )
                    else
                      DropdownButtonFormField<int>(
                        initialValue: _creditCardId,
                        isExpanded: true,
                        decoration: _inputDeco(
                          label: 'Cartão',
                          icon: Icons.credit_card_rounded,
                        ),
                        items: _creditCards
                            .map(
                              (card) => DropdownMenuItem(
                                value: card.id,
                                child: Text(card.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          _creditCardId = value;
                          if (_paymentMethod ==
                              TxItem.creditCardBillPaymentMethod) {
                            final selected = _creditCards.where(
                              (card) => card.id == value,
                            );
                            if (selected.isNotEmpty &&
                                selected.first.accountId != null) {
                              _accountId = selected.first.accountId;
                            }
                          }
                        }),
                      ),
                  ],
                  if (_accounts.isNotEmpty &&
                      (_isIncome ||
                          _paymentMethod != TxItem.creditPaymentMethod)) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: _accountId,
                      isExpanded: true,
                      decoration: _inputDeco(
                        label: _isIncome
                            ? 'Conta de destino'
                            : _paymentMethod ==
                                  TxItem.creditCardBillPaymentMethod
                            ? 'Conta que pagou'
                            : 'Conta',
                        icon: Icons.account_balance_wallet_rounded,
                      ),
                      items: _accounts
                          .map(
                            (account) => DropdownMenuItem(
                              value: account.id,
                              child: Text(account.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _accountId = value),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _isIncome
                        ? 'Dica: marque “Salário” quando for seu pagamento mensal.'
                        : _paymentMethod == TxItem.creditCardBillPaymentMethod
                        ? 'Quita compras no crédito e não soma outra despesa.'
                        : 'Use “Crédito” na compra e “Pagamento da fatura” ao quitar o cartão.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            if (_isInvestmentIncome) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.trending_up_rounded),
                          SizedBox(width: 8),
                          Text(
                            'Investimento',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _investmentKind,
                        isExpanded: true,
                        decoration: inputDeco(
                          label: 'Tipo',
                          icon: Icons.trending_up_rounded,
                        ),
                        items: _investmentKinds
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e,
                                child: Text(e),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _investmentKind = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _invAssetCtrl,
                        decoration: inputDeco(
                          label: 'Ativo / Título (opcional)',
                          hint: 'Ex: PETR4, MXRF11, Tesouro Selic 2031…',
                          icon: Icons.confirmation_number_rounded,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AdaptivePair(
                        first: TextField(
                          controller: _invQtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: inputDeco(
                            label: 'Quantidade (opcional)',
                            hint: 'Ex: 10',
                            icon: Icons.numbers_rounded,
                          ),
                        ),
                        second: TextField(
                          controller: _invBrokerCtrl,
                          decoration: inputDeco(
                            label: 'Banco/Corretora (opcional)',
                            hint: 'Ex: Nubank, BTG…',
                            icon: Icons.account_balance_wallet_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Vai para o extrato normal. Depois você pode criar um extrato só de investimentos no Dashboard filtrando por categoria.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('Cupom e comprovante'),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: .12),
                          cs.secondary.withValues(alpha: .07),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: .22),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              child: const Icon(Icons.qr_code_scanner_rounded),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ler QR Code da NFC-e',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'A câmera detecta automaticamente, sem tirar ou salvar uma foto.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _isExtractingReceipt
                              ? null
                              : _scanReceiptQr,
                          icon: _isExtractingReceipt
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.center_focus_strong_rounded),
                          label: Text(
                            _isExtractingReceipt
                                ? 'Consultando cupom…'
                                : 'Abrir leitor ao vivo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_receiptItemsDraft.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: .24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_receiptItemsDraft.length} ${_receiptItemsDraft.length == 1 ? 'item identificado' : 'itens identificados'} ${_receiptItemsSource == _ReceiptItemsSource.qr ? 'pelo QR Code' : 'pela imagem'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final it in _receiptItemsDraft.take(5))
                                Chip(
                                  label: Text(
                                    '${it.name} • R\$ ${it.price.toStringAsFixed(2).replaceAll('.', ',')}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (_receiptItemsDraft.length > 5)
                                Chip(
                                  label: Text(
                                    '+${_receiptItemsDraft.length - 5}',
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: _reviewReceiptItems,
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Revisar itens'),
                              ),
                              TextButton.icon(
                                onPressed: _clearReceiptItems,
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Remover itens'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Divider(color: cs.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'ANEXO OPCIONAL',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: cs.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _imagePath != null
                        ? Material(
                            key: const ValueKey('img'),
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _openImagePreview,
                              borderRadius: BorderRadius.circular(16),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  height: 150,
                                  color: cs.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: Image.file(
                                    File(_imagePath!),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            key: const ValueKey('empty'),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.receipt_long_outlined),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Você também pode anexar uma foto do comprovante.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  AdaptivePair(
                    gap: 10,
                    first: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Tirar foto'),
                    ),
                    second: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galeria'),
                    ),
                  ),
                  if (_imagePath != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isExtractingReceipt
                          ? null
                          : _extractReceiptItems,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Extrair itens desta imagem'),
                    ),
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

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('Observação'),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    decoration: _inputDeco(
                      label: 'Opcional',
                      hint: 'Ex: pagamento dividido, local, etc.',
                      icon: Icons.note_alt,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            if (_hasChanges)
              Text(
                'Você tem alterações não salvas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
