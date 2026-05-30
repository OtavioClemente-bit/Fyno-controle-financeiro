import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import '../repositories/notification_import_repository.dart';
import '../notification_bridge.dart';
import 'pending_notifications_page.dart';
import 'select_bank_apps_page.dart';

class NotificationsHubPage extends StatefulWidget {
  const NotificationsHubPage({super.key});

  @override
  State<NotificationsHubPage> createState() => _NotificationsHubPageState();
}

class _NotificationsHubPageState extends State<NotificationsHubPage>
    with WidgetsBindingObserver {
  final NotificationImportRepository _repo = NotificationImportRepository();

  bool _loading = true;
  bool _listenerEnabled = false;
  bool _capturing = false;

  Set<String> _allowedPackages = {};
  int _pendingCount = 0;

  final List<Map<String, String>> _live = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCapture();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // quando volta da tela de permissão
    if (state == AppLifecycleState.resumed) {
      _boot();
    }
  }

  Future<void> _boot() async {
    try {
      final enabled = await NotificationBridge.instance
          .isNotificationListenerEnabled();
      final allowed = await _repo.getEnabledPackages();
      final pending = await _repo.countPending();

      _listenerEnabled = enabled;
      _allowedPackages = allowed;
      _pendingCount = pending;

      if (_listenerEnabled) {
        _startCapture();
      } else {
        await _stopCapture();
      }
    } catch (_) {
      // ignore
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openListenerSettings() async {
    await NotificationBridge.instance.openNotificationListenerSettings();
    // _boot() será chamado no resumed
  }

  Future<void> _pickApps() async {
    final res = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(builder: (_) => const SelectBankAppsPage()),
    );
    if (res == null) return;

    setState(() => _allowedPackages = res);

    // Reinicia captura com filtro novo
    await _stopCapture();
    await _boot();
  }

  Future<void> _openInbox() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PendingNotificationsPage()));
    // recarrega contador
    setState(() => _loading = true);
    await _boot();
  }

  void _startCapture() {
    if (_capturing) return;
    _capturing = true;

    NotificationBridge.instance.start(
      allowedPackages: _allowedPackages.isEmpty ? null : _allowedPackages,
      onEvent: (ServiceNotificationEvent event) async {
        final pkg = (event.packageName ?? '').toString().trim();
        final title = (event.title ?? '').toString().trim();
        final text = (event.content ?? '').toString().trim();

        if (pkg.isEmpty) return;

        final postedAtMs = DateTime.now().millisecondsSinceEpoch;
        final key = '$pkg|$postedAtMs|${title.hashCode}|${text.hashCode}';

        // salva no DB (pending)
        await _repo.insertPending(
          notifKey: key,
          packageName: pkg,
          title: title,
          text: text,
          postedAtMs: postedAtMs,
          rawJson: jsonEncode({
            'packageName': pkg,
            'title': title,
            'text': text,
            'postedAtMs': postedAtMs,
          }),
        );

        final pending = await _repo.countPending();

        if (!mounted) return;
        setState(() {
          _pendingCount = pending;
          _live.insert(0, {
            'app': pkg,
            'title': title.isNotEmpty ? title : '(sem título)',
            'text': text.isNotEmpty ? text : '(vazio)',
          });
          if (_live.length > 12) _live.removeLast();
        });
      },
    );
  }

  Future<void> _stopCapture() async {
    if (!_capturing) return;
    _capturing = false;
    await NotificationBridge.instance.stop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          IconButton(
            tooltip: 'Selecionar apps',
            onPressed: _pickApps,
            icon: const Icon(Icons.filter_alt_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _infoCard(cs),
          const SizedBox(height: 12),
          _actionCard(
            context,
            title: 'Caixa de entrada',
            subtitle:
                'Veja notificações capturadas e converta em despesa ou receita com 1 toque.',
            trailing: _pendingCount == 0
                ? '0 pendentes'
                : '$_pendingCount pendente(s)',
            icon: Icons.inbox_rounded,
            onTap: _openInbox,
          ),
          const SizedBox(height: 12),
          Text(
            'Captura ao vivo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (!_listenerEnabled)
            _warningTile(
              cs,
              title: 'Permissão desativada',
              subtitle:
                  'Ative o acesso às notificações para capturar automaticamente.',
              actionText: 'Ativar',
              onAction: _openListenerSettings,
            )
          else
            _liveList(cs),
        ],
      ),
    );
  }

  Widget _infoCard(ColorScheme cs) {
    final filterLabel = _allowedPackages.isEmpty
        ? 'Todos os apps'
        : '${_allowedPackages.length} app(s) selecionado(s)';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _listenerEnabled ? Icons.check_circle : Icons.warning_amber,
              color: _listenerEnabled ? cs.primary : cs.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _listenerEnabled
                        ? 'Captura habilitada'
                        : 'Captura desabilitada',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    filterLabel,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: _pickApps, child: const Text('Filtros')),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String trailing,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Text(trailing, style: TextStyle(color: cs.onSurfaceVariant)),
      ),
    );
  }

  Widget _warningTile(
    ColorScheme cs, {
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onAction,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: cs.error),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            FilledButton(onPressed: onAction, child: Text(actionText)),
          ],
        ),
      ),
    );
  }

  Widget _liveList(ColorScheme cs) {
    if (_live.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Ainda nada… abra o app do banco e faça uma compra/teste.',
          ),
        ),
      );
    }

    return Column(
      children: _live.map((n) {
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n['title'] ?? '(sem título)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(n['text'] ?? '(vazio)'),
                const SizedBox(height: 8),
                Text(
                  n['app'] ?? '',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
