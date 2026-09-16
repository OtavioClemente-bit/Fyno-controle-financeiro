import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../bank_app_catalog.dart';
import '../notification_bridge.dart';
import '../notification_inbox_service.dart';
import '../repositories/notification_import_repository.dart';
import 'pending_notifications_page.dart';
import 'financial_intelligence_page.dart';
import 'select_bank_apps_page.dart';

class NotificationsHubPage extends StatefulWidget {
  const NotificationsHubPage({super.key});

  @override
  State<NotificationsHubPage> createState() => _NotificationsHubPageState();
}

class _NotificationsHubPageState extends State<NotificationsHubPage>
    with WidgetsBindingObserver {
  final _repository = NotificationImportRepository();
  final _inboxService = NotificationInboxService();
  Timer? _syncTimer;
  bool _syncInProgress = false;

  bool _loading = true;
  bool _listenerEnabled = false;
  bool _captureEnabled = false;
  bool _backgroundStartupSettingsAvailable = false;
  bool _rebindAfterBackgroundSettings = false;
  int _pendingCount = 0;
  int _reminderCount = 0;
  Set<String> _allowedPackages = const {};
  NotificationDiagnostics _diagnostics = const NotificationDiagnostics.empty();

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _ready =>
      _supported &&
      _listenerEnabled &&
      _captureEnabled &&
      _allowedPackages.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _syncTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _poll() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      await _load();
    } finally {
      _syncInProgress = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_rebindAfterBackgroundSettings) {
      _rebindAfterBackgroundSettings = false;
      unawaited(_rebindAfterReturningFromSettings());
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!_supported) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final listener = await NotificationBridge.instance
        .isNotificationListenerEnabled();
    final capture = await NotificationBridge.instance.isCaptureEnabled();
    final backgroundStartupSettings = await NotificationBridge.instance
        .hasBackgroundStartupSettings();
    final packages = await _repository.getEnabledPackages();
    final pending = await _inboxService.sync();
    final reminders = await _repository.countScheduledReminders();
    final diagnostics = await NotificationBridge.instance.getDiagnostics();
    if (!mounted) return;
    setState(() {
      _listenerEnabled = listener;
      _captureEnabled = capture;
      _backgroundStartupSettingsAvailable = backgroundStartupSettings;
      _allowedPackages = packages;
      _pendingCount = pending;
      _reminderCount = reminders;
      _diagnostics = diagnostics;
      _loading = false;
    });
  }

  Future<void> _chooseBanks() async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(builder: (_) => const SelectBankAppsPage()),
    );
    if (selected == null || !mounted) return;
    setState(() => _allowedPackages = selected);
    await _load();
  }

  Future<bool> _showDisclosure() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.shield_outlined, size: 36),
            title: const Text('Antes de ativar'),
            content: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'O Fyno acessa o texto das notificações dos bancos que você '
                    'escolher, inclusive com o aplicativo fechado, para identificar '
                    'valor, entrada ou saída e forma de pagamento.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'O processamento e o armazenamento acontecem somente neste '
                    'aparelho. O conteúdo não é enviado nem compartilhado.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Códigos, senhas, tokens, alertas de acesso, ofertas e '
                    'notificações sem uma transação reconhecida são descartados.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Agora não'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Concordar e continuar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _activate() async {
    if (!_supported) return;
    if (_allowedPackages.isEmpty) {
      await _chooseBanks();
      if (!mounted) return;
      if (_allowedPackages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escolha pelo menos um banco.')),
        );
        return;
      }
    }

    if (!await _showDisclosure()) return;
    final activated = await NotificationBridge.instance.setCaptureEnabled(true);
    if (!activated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível ativar neste aparelho.'),
        ),
      );
      return;
    }
    if (!_listenerEnabled) {
      await NotificationBridge.instance.openNotificationListenerSettings();
    } else {
      await NotificationBridge.instance.requestRebind();
    }
    await _load();
  }

  Future<void> _pause() async {
    await NotificationBridge.instance.setCaptureEnabled(false);
    await _load();
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PendingNotificationsPage()),
    );
    await _load();
  }

  Future<void> _openIntelligence() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const FinancialIntelligencePage()),
    );
    await _load();
  }

  Future<void> _repairAccess() async {
    if (!_listenerEnabled) {
      await NotificationBridge.instance.openNotificationListenerSettings();
    } else {
      await NotificationBridge.instance.requestRebind();
      // requestRebind apenas envia um pedido ao Android. Fabricantes como
      // Xiaomi/POCO podem recusá-lo quando a inicialização automática está
      // bloqueada, portanto só confirmamos depois do callback nativo real.
      await Future<void>.delayed(const Duration(seconds: 2));
      final diagnostics = await NotificationBridge.instance.getDiagnostics();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              diagnostics.listenerConnected
                  ? 'Serviço de detecção conectado ao Android.'
                  : 'O Android não reconectou o serviço. Em Xiaomi/POCO, '
                        'ative a inicialização automática do Fyno.',
            ),
          ),
        );
      }
    }
    await _load();
  }

  Future<void> _openNotificationAccessSettings() async {
    final opened = await NotificationBridge.instance
        .openNotificationListenerSettings();
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Não foi possível abrir o acesso às notificações.'),
      ),
    );
  }

  Future<void> _openBackgroundStartupSettings() async {
    _rebindAfterBackgroundSettings = true;
    final opened = await NotificationBridge.instance
        .openBackgroundStartupSettings();
    if (opened || !mounted) return;
    _rebindAfterBackgroundSettings = false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Não foi possível abrir a configuração neste aparelho.'),
      ),
    );
  }

  Future<void> _rebindAfterReturningFromSettings() async {
    if (_listenerEnabled) {
      await NotificationBridge.instance.requestRebind();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    await _load();
  }

  Future<void> _runSelfTest() async {
    final created = await NotificationBridge.instance.runSelfTest();
    if (created) await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created
              ? 'Teste criado. Abra as sugestões para revisar o item de R\$ 0,01.'
              : 'Ative a detecção e escolha um banco antes de testar.',
        ),
      ),
    );
  }

  void _showPrivacyDetails() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        maxChildSize: .92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: const [
            Icon(Icons.privacy_tip_outlined, size: 38),
            SizedBox(height: 12),
            Text(
              'Privacidade das transações detectadas',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 16),
            _PrivacyItem(
              title: 'O que é acessado',
              text:
                  'Somente alertas dos bancos escolhidos. O filtro procura uma moeda '
                  'e uma movimentação clara, como compra aprovada ou Pix recebido.',
            ),
            _PrivacyItem(
              title: 'O que é descartado',
              text:
                  'Tokens, senhas, códigos de verificação, alertas de login, '
                  'publicidade, faturas e mensagens que não sejam uma transação.',
            ),
            _PrivacyItem(
              title: 'Onde fica',
              text:
                  'No armazenamento privado do Fyno neste aparelho. Nenhuma '
                  'notificação é enviada ou compartilhada pelo recurso.',
            ),
            _PrivacyItem(
              title: 'Lembretes sob seu controle',
              text:
                  'A permissão para o Fyno mostrar notificações próprias só é '
                  'pedida quando você agenda um lembrete. Sem ela, o item '
                  'continua organizado dentro da caixa inteligente.',
            ),
            _PrivacyItem(
              title: 'Você decide',
              text:
                  'Toda sugestão precisa ser revisada antes de virar receita ou '
                  'despesa. A captura pode ser pausada a qualquer momento.',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final banksByPrimary = <String, BankAppDefinition>{};
    for (final packageName in _allowedPackages) {
      final bank = bankByPackage(packageName);
      if (bank != null) banksByPrimary[bank.packageName] = bank;
    }
    final banks = banksByPrimary.values.toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Transações detectadas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (!_supported) ...[
                  const _UnsupportedPlatformCard(),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.primaryContainer,
                        colors.secondaryContainer,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _ready
                                ? Icons.check_circle_rounded
                                : Icons.pause_circle_rounded,
                            color: _ready
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            !_supported
                                ? 'Disponível no Android'
                                : _ready
                                ? 'Detecção ativa'
                                : 'Configuração incompleta',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _ready
                            ? 'O Fyno aguarda uma transação dos ${banks.length} banco(s) selecionado(s).'
                            : !_supported
                            ? 'A leitura local de notificações bancárias depende do serviço seguro do Android.'
                            : 'Conclua os passos abaixo para receber sugestões de receitas e despesas.',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: _ready
                            ? OutlinedButton.icon(
                                onPressed: _pause,
                                icon: const Icon(Icons.pause_rounded),
                                label: const Text('Pausar detecção'),
                              )
                            : FilledButton.icon(
                                onPressed: _supported ? _activate : null,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Ativar com segurança'),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _HubCard(
                  icon: Icons.account_balance_rounded,
                  title: 'Bancos observados',
                  subtitle: banks.isEmpty
                      ? 'Nenhum banco selecionado'
                      : banks.map((bank) => bank.name).join(', '),
                  actionLabel: 'Escolher bancos',
                  onTap: _chooseBanks,
                ),
                const SizedBox(height: 12),
                if (_supported) ...[
                  _DiagnosticsCard(
                    diagnostics: _diagnostics,
                    listenerEnabled: _listenerEnabled,
                    captureEnabled: _captureEnabled,
                    banksSelected: banks.isNotEmpty,
                    onRepair: _repairAccess,
                    onOpenAccessSettings: _openNotificationAccessSettings,
                    showBackgroundSettings: _backgroundStartupSettingsAvailable,
                    onOpenBackgroundSettings: _openBackgroundStartupSettings,
                    onTest: _runSelfTest,
                  ),
                  const SizedBox(height: 12),
                ],
                _HubCard(
                  icon: Icons.inbox_rounded,
                  title: 'Aguardando sua revisão',
                  subtitle: _pendingCount == 0 && _reminderCount == 0
                      ? 'Nenhuma movimentação pendente'
                      : '$_pendingCount para revisar • $_reminderCount lembrete(s)',
                  actionLabel: 'Abrir caixa inteligente',
                  onTap: _openInbox,
                  badge: _pendingCount,
                ),
                const SizedBox(height: 12),
                _HubCard(
                  icon: Icons.psychology_alt_rounded,
                  title: 'Inteligência financeira',
                  subtitle:
                      'Regras aprendidas, assinaturas e contas recorrentes detectadas no aparelho.',
                  actionLabel: 'Ver análise inteligente',
                  onTap: _openIntelligence,
                ),
                const SizedBox(height: 12),
                _HubCard(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacidade e proteção',
                  subtitle:
                      'Processamento local, filtro de dados sensíveis e controle total.',
                  actionLabel: 'Ver detalhes',
                  onTap: _showPrivacyDetails,
                ),
              ],
            ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: Badge(
                    isLabelVisible: badge > 0,
                    label: Text('$badge'),
                    child: Icon(icon),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyItem extends StatelessWidget {
  const _PrivacyItem({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(text),
      ],
    ),
  );
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.diagnostics,
    required this.listenerEnabled,
    required this.captureEnabled,
    required this.banksSelected,
    required this.onRepair,
    required this.onOpenAccessSettings,
    required this.showBackgroundSettings,
    required this.onOpenBackgroundSettings,
    required this.onTest,
  });

  final NotificationDiagnostics diagnostics;
  final bool listenerEnabled;
  final bool captureEnabled;
  final bool banksSelected;
  final VoidCallback onRepair;
  final VoidCallback onOpenAccessSettings;
  final bool showBackgroundSettings;
  final VoidCallback onOpenBackgroundSettings;
  final VoidCallback onTest;

  String _when(DateTime? date) {
    if (date == null) return 'ainda não';
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inMinutes < 1) return 'agora';
    if (difference.inHours < 1) return 'há ${difference.inMinutes} min';
    if (difference.inDays < 1) return 'há ${difference.inHours} h';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final serviceOk = listenerEnabled && diagnostics.listenerConnected;
    final allOk = serviceOk && captureEnabled && banksSelected;
    final lastEvent = diagnostics.lastCapturedAt != null
        ? 'Última transação detectada ${_when(diagnostics.lastCapturedAt)}.'
        : diagnostics.lastSeenAt != null
        ? 'O Android entregou um alerta ${_when(diagnostics.lastSeenAt)}, mas nenhuma transação foi reconhecida.'
        : 'O Android ainda não entregou notificações ao Fyno.';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allOk
                      ? Icons.health_and_safety_rounded
                      : Icons.build_circle_outlined,
                  color: allOk ? colors.primary : colors.tertiary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Diagnóstico da detecção',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  allOk ? 'Pronto' : 'Verificar',
                  style: TextStyle(
                    color: allOk ? colors.primary : colors.tertiary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DiagnosticLine(label: 'Acesso do Android', ok: listenerEnabled),
            _DiagnosticLine(label: 'Serviço conectado', ok: serviceOk),
            _DiagnosticLine(label: 'Captura ativada', ok: captureEnabled),
            _DiagnosticLine(label: 'Banco selecionado', ok: banksSelected),
            const SizedBox(height: 10),
            Text(lastEvent, style: TextStyle(color: colors.onSurfaceVariant)),
            if (diagnostics.lastRejectionReason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Último descarte: ${diagnostics.lastRejectionReason}.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
            if (showBackgroundSettings) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Em Xiaomi, Redmi e POCO, permita que o Fyno inicie em '
                  'segundo plano. Na próxima tela, procure Fyno e ative a chave.',
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onRepair,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    listenerEnabled ? 'Reconectar' : 'Liberar acesso',
                  ),
                ),
                if (listenerEnabled && !diagnostics.listenerConnected)
                  FilledButton.tonalIcon(
                    onPressed: onOpenAccessSettings,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Renovar acesso'),
                  ),
                if (showBackgroundSettings)
                  FilledButton.tonalIcon(
                    onPressed: onOpenBackgroundSettings,
                    icon: const Icon(Icons.settings_suggest_rounded),
                    label: const Text('Permitir em segundo plano'),
                  ),
                TextButton.icon(
                  onPressed: captureEnabled && banksSelected ? onTest : null,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Executar teste'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 18,
          color: ok
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    ),
  );
}

class _UnsupportedPlatformCard extends StatelessWidget {
  const _UnsupportedPlatformCard();

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.android_rounded),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'A detecção automática por notificações funciona no Android. '
              'Neste dispositivo, continue adicionando transações manualmente ou pelo QR Code.',
            ),
          ),
        ],
      ),
    ),
  );
}
