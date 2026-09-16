import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/widgets/app_settings_sheet.dart';
import 'backup_restore_page.dart';
import 'financial_reminder_page.dart';
import 'notifications/models/pages/notifications_hub_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const _nameKey = 'profile_display_name';
  String _name = 'Seu perfil';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _name = prefs.getString(_nameKey) ?? _name);
  }

  Future<void> _editName() async {
    var value = _name == 'Seu perfil' ? '' : _name;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Como podemos chamar você?'),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Seu nome'),
          onChanged: (text) => value = text,
          onFieldSubmitted: (_) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, result);
    if (mounted) setState(() => _name = result);
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _about() {
    showAboutDialog(
      context: context,
      applicationName: 'Fyno',
      applicationVersion: '1.21.1',
      applicationIcon: const CircleAvatar(
        child: Icon(Icons.account_balance_wallet_rounded),
      ),
      children: const [
        Text(
          'Controle financeiro pessoal criado para mostrar com clareza para onde seu dinheiro está indo.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Perfil'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      _name == 'Seu perfil' ? 'F' : _name[0].toUpperCase(),
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Seu espaço no Fyno',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar nome',
                    onPressed: _editName,
                    icon: const Icon(Icons.edit_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _GroupTitle('Preferências'),
          _ProfileTile(
            icon: Icons.palette_outlined,
            title: 'Aparência e preferências',
            subtitle: 'Tema claro, escuro e ajustes',
            onTap: () => AppSettingsSheet.show(
              context,
              onOpenPermissions: () {
                Navigator.of(context).pop();
                _open(const NotificationsHubPage());
              },
              onOpenBackup: () {
                Navigator.of(context).pop();
                _open(const BackupRestorePage());
              },
            ),
          ),
          _ProfileTile(
            icon: Icons.alarm_rounded,
            title: 'Lembretes financeiros',
            subtitle: 'Reserve um momento para colocar tudo em dia',
            onTap: () => _open(const FinancialReminderPage()),
          ),
          _ProfileTile(
            icon: Icons.notifications_outlined,
            title: 'Notificações e bancos',
            subtitle: 'Transações detectadas e lembretes',
            onTap: () => _open(const NotificationsHubPage()),
          ),
          const SizedBox(height: 18),
          const _GroupTitle('Seus dados'),
          _ProfileTile(
            icon: Icons.cloud_sync_outlined,
            title: 'Backup e restauração',
            subtitle: 'Proteja ou recupere seus registros',
            onTap: () => _open(const BackupRestorePage()),
          ),
          const SizedBox(height: 18),
          const _GroupTitle('Aplicativo'),
          _ProfileTile(
            icon: Icons.info_outline_rounded,
            title: 'Sobre o Fyno',
            subtitle: 'Versão, proposta e informações',
            onTap: _about,
          ),
          _ProfileTile(
            icon: Icons.shield_outlined,
            title: 'Privacidade',
            subtitle: 'Seus dados financeiros ficam sob seu controle',
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text('Privacidade'),
                content: Text(
                  'O Fyno organiza seus dados financeiros no dispositivo. Recursos externos, como backup, só são usados quando você solicita.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    elevation: 0,
    child: ListTile(
      minTileHeight: 68,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
