import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';

import '../repositories/notification_import_repository.dart';

class SelectBankAppsPage extends StatefulWidget {
  const SelectBankAppsPage({super.key});

  @override
  State<SelectBankAppsPage> createState() => _SelectBankAppsPageState();
}

class _SelectBankAppsPageState extends State<SelectBankAppsPage> {
  final NotificationImportRepository _repo = NotificationImportRepository();

  bool _loading = true;
  bool _showSystemApps = false;
  String _query = '';

  List<Application> _apps = <Application>[];
  Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final selected = await _repo.getEnabledPackages();

    // Só apps com launch intent (evita serviços "fantasmas")
    final apps = await DeviceApps.getInstalledApplications(
      includeAppIcons: true,
      includeSystemApps: _showSystemApps,
      onlyAppsWithLaunchIntent: true,
    );

    apps.sort(
      (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
    );

    if (!mounted) return;
    setState(() {
      _selected = selected;
      _apps = apps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final filtered = _apps.where((a) {
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return a.appName.toLowerCase().contains(q) ||
          a.packageName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escolher bancos'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar app… (ex: nubank, inter, itau)',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Selecionados: ${_selected.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Switch(
                            value: _showSystemApps,
                            onChanged: (v) async {
                              setState(() => _showSystemApps = v);
                              await _load();
                            },
                          ),
                          const SizedBox(width: 8),
                          const Text('Sistema'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Marque apenas apps de bancos/contas digitais.\n'
                          'Seu app só vai ler notificações desses apps.',
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final app = filtered[i];
                      final pkg = app.packageName;
                      final checked = _selected.contains(pkg);

                      final icon = (app is ApplicationWithIcon)
                          ? app.icon
                          : null;

                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) async {
                          final enabled = v ?? false;
                          setState(() {
                            if (enabled) {
                              _selected.add(pkg);
                            } else {
                              _selected.remove(pkg);
                            }
                          });
                          await _repo.setPackageEnabled(
                            packageName: pkg,
                            enabled: enabled,
                          );
                        },
                        title: Text(
                          app.appName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(pkg),
                        secondary: icon == null
                            ? CircleAvatar(
                                backgroundColor: cs.surfaceContainerHighest,
                                child: const Icon(
                                  Icons.account_balance_rounded,
                                ),
                              )
                            : CircleAvatar(
                                backgroundColor: cs.surfaceContainerHighest,
                                backgroundImage: MemoryImage(icon),
                              ),
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
