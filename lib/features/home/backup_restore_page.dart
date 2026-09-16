import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'drive_backup_service.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final _service = DriveBackupService.instance;
  final _date = DateFormat("dd 'de' MMMM 'de' yyyy, HH:mm", 'pt_BR');

  List<CloudBackupInfo> _backups = const <CloudBackupInfo>[];
  bool _busy = false;
  bool _loadingBackups = false;
  bool _restored = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    await _service.initialize();
    if (!mounted) return;
    setState(() {});
    if (_service.isConnected) await _loadBackups();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.connect();
      await _loadBackups();
    } on DriveBackupException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadBackups() async {
    if (!_service.isConnected) return;
    setState(() {
      _loadingBackups = true;
      _error = null;
    });
    try {
      final backups = await _service.listBackups();
      if (mounted) setState(() => _backups = backups);
    } on DriveBackupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loadingBackups = false);
    }
  }

  Future<void> _backupNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.backupNow();
      await _loadBackups();
      if (!mounted) return;
      final imageText = result.imagesSkipped > 0
          ? '${result.imagesIncluded} imagens incluídas e ${result.imagesSkipped} ignoradas por limite ou arquivo ausente.'
          : '${result.imagesIncluded} imagens de comprovantes incluídas.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cópia salva no Google Drive. $imageText'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on DriveBackupException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askRestore(CloudBackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.settings_backup_restore_rounded),
        title: const Text('Restaurar esta cópia?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_date.format(backup.createdAt.toLocal())),
            const SizedBox(height: 12),
            const Text(
              'Os dados financeiros atuais deste aparelho serão substituídos. Antes disso, o Fyno cria uma cópia local temporária e só conclui após validar o arquivo.',
            ),
            const SizedBox(height: 12),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notificações capturadas e a lista de apps monitorados não mudam.',
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurar dados'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.restore(backup);
      _restored = true;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.cloud_done_rounded),
          title: const Text('Restauração concluída'),
          content: Text(
            '${result.transactionCount} lançamentos foram recuperados'
            '${result.imagesRestored > 0 ? ', com ${result.imagesRestored} imagens de comprovantes' : ''}.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Concluir'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on DriveBackupException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut({required bool revoke}) async {
    setState(() => _busy = true);
    try {
      if (revoke) {
        await _service.disconnect();
      } else {
        await _service.signOut();
      }
      if (mounted) {
        setState(() {
          _backups = const <CloudBackupInfo>[];
          _error = null;
        });
      }
    } catch (_) {
      _showError('Não foi possível desconectar a conta agora.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCloudBackups() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded),
        title: const Text('Excluir cópias da nuvem?'),
        content: const Text(
          'As cópias privadas serão apagadas permanentemente do Google Drive. Os dados deste celular não serão alterados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir cópias'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.deleteAllBackups();
      if (!mounted) return;
      setState(() => _backups = const <CloudBackupInfo>[]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cópias removidas do Google Drive.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on DriveBackupException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final account = _service.account;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) {},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Backup Google'),
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _restored),
          ),
          actions: [
            if (account != null)
              PopupMenuButton<String>(
                tooltip: 'Opções da conta',
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteCloudBackups();
                  } else {
                    _signOut(revoke: value == 'revoke');
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Excluir cópias da nuvem'),
                  ),
                  PopupMenuItem(
                    value: 'signout',
                    child: Text('Sair da conta neste aparelho'),
                  ),
                  PopupMenuItem(
                    value: 'revoke',
                    child: Text('Remover acesso do Fyno'),
                  ),
                ],
              ),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  28 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  _PrivacyBanner(colorScheme: cs),
                  const SizedBox(height: 16),
                  if (account == null)
                    _DisconnectedCard(
                      initializing: _service.isInitializing,
                      error: _service.configurationError,
                      onConnect: _busy ? null : _connect,
                    )
                  else ...[
                    _AccountCard(
                      name: account.displayName,
                      email: account.email,
                      photoUrl: account.photoUrl,
                      lastBackupAt: _service.lastBackupAt,
                      date: _date,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _backupNow,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Fazer backup agora'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cópias disponíveis',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: _loadingBackups || _busy
                              ? null
                              : _loadBackups,
                          tooltip: 'Atualizar lista',
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loadingBackups)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_backups.isEmpty)
                      const _EmptyBackups()
                    else
                      ..._backups.map(
                        (backup) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BackupCard(
                            backup: backup,
                            date: _date,
                            onRestore: _busy ? null : () => _askRestore(backup),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const _IncludedDataCard(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorCard(message: _error!),
                  ],
                ],
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: cs.scrim.withValues(alpha: .26),
                  child: const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text('Protegendo seus dados…'),
                          ],
                        ),
                      ),
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

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner({required this.colorScheme});
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, color: colorScheme.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privado por padrão',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'O Fyno usa uma área oculta do Google Drive. Nenhum outro aplicativo pode abrir essas cópias.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisconnectedCard extends StatelessWidget {
  const _DisconnectedCard({
    required this.initializing,
    required this.error,
    required this.onConnect,
  });

  final bool initializing;
  final String? error;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_sync_rounded, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'Leve seus dados para o próximo celular',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Conecte sua conta Google para salvar e recuperar suas informações com segurança.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: initializing ? null : onConnect,
              icon: initializing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.account_circle_rounded),
              label: Text(
                initializing ? 'Verificando conta…' : 'Conectar conta Google',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.lastBackupAt,
    required this.date,
  });

  final String? name;
  final String email;
  final String? photoUrl;
  final DateTime? lastBackupAt;
  final DateFormat date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              foregroundImage: photoUrl == null
                  ? null
                  : NetworkImage(photoUrl!),
              child: const Icon(Icons.person_rounded),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name?.trim().isNotEmpty == true
                              ? name!
                              : 'Conta Google',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.verified_rounded, size: 18, color: cs.primary),
                    ],
                  ),
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    lastBackupAt == null
                        ? 'Nenhum backup feito neste aparelho'
                        : 'Último envio: ${date.format(lastBackupAt!.toLocal())}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary,
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

class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.backup,
    required this.date,
    required this.onRestore,
  });

  final CloudBackupInfo backup;
  final DateFormat date;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.cloud_done_rounded,
                color: cs.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date.format(backup.createdAt.toLocal()),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatBytes(backup.sizeBytes)}'
                    '${backup.transactionCount == null ? '' : ' • ${backup.transactionCount} lançamentos'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onRestore, child: const Text('Restaurar')),
          ],
        ),
      ),
    );
  }
}

class _EmptyBackups extends StatelessWidget {
  const _EmptyBackups();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: const Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 34),
          SizedBox(height: 10),
          Text('Ainda não há cópias nesta conta.'),
          SizedBox(height: 4),
          Text(
            'Faça o primeiro backup para proteger seus dados.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _IncludedDataCard extends StatelessWidget {
  const _IncludedDataCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'O que é protegido',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          _IncludedRow(text: 'Lançamentos, categorias e formas de pagamento'),
          _IncludedRow(text: 'Produtos e itens extraídos de notas fiscais'),
          _IncludedRow(text: 'Veículos e histórico de abastecimentos'),
          _IncludedRow(text: 'Comprovantes disponíveis e preferência de tema'),
          Divider(height: 24),
          _IncludedRow(
            text: 'Notificações bancárias ficam somente neste celular',
            included: false,
          ),
        ],
      ),
    );
  }
}

class _IncludedRow extends StatelessWidget {
  const _IncludedRow({required this.text, this.included = true});
  final String text;
  final bool included;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            included ? Icons.check_circle_rounded : Icons.shield_outlined,
            size: 19,
            color: included ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: cs.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return 'tamanho indisponível';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}
