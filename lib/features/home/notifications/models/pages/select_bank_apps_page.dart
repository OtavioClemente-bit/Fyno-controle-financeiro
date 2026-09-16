import 'package:flutter/material.dart';

import '../bank_app_catalog.dart';
import '../notification_bridge.dart';
import '../repositories/notification_import_repository.dart';

class SelectBankAppsPage extends StatefulWidget {
  const SelectBankAppsPage({super.key});

  @override
  State<SelectBankAppsPage> createState() => _SelectBankAppsPageState();
}

class _SelectBankAppsPageState extends State<SelectBankAppsPage> {
  final _repository = NotificationImportRepository();
  final _selected = <String>{};
  bool _loading = true;
  bool _saving = false;
  String _query = '';
  Set<String> _installedPackages = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _repository.getEnabledPackages();
    final installed = await NotificationBridge.instance.getInstalledPackages(
      allBankPackageNames,
    );
    if (!mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(
          bankAppCatalog
              .where((bank) => bank.allPackageNames.any(enabled.contains))
              .map((bank) => bank.packageName),
        );
      _installedPackages = installed;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final expanded = bankAppCatalog
        .where((bank) => _selected.contains(bank.packageName))
        .expand((bank) => bank.allPackageNames)
        .toSet();
    await _repository.setEnabledPackages(expanded);
    await NotificationBridge.instance.setAllowedPackages(expanded);
    if (!mounted) return;
    Navigator.of(context).pop(expanded);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final visible = bankAppCatalog
        .where((bank) => bank.name.toLowerCase().contains(query))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seus bancos'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Salvando…' : 'Salvar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: colors.primary),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Escolha os bancos que podem gerar sugestões. O Fyno '
                          'identifica quais deles estão instalados sem acessar '
                          'contas, saldos ou senhas.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Buscar banco',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                ...visible.map((bank) {
                  final selected = _selected.contains(bank.packageName);
                  final installed = bank.allPackageNames.any(
                    _installedPackages.contains,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: CheckboxListTile(
                        value: selected,
                        onChanged: (value) {
                          setState(() {
                            if (value ?? false) {
                              _selected.add(bank.packageName);
                            } else {
                              _selected.remove(bank.packageName);
                            }
                          });
                        },
                        title: Text(
                          bank.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          installed
                              ? 'Instalado neste aparelho'
                              : 'Não identificado neste aparelho',
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: bank.color,
                          foregroundColor: Colors.white,
                          child: Text(
                            bank.initials,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
