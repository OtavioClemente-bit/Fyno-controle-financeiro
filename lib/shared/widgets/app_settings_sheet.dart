import 'package:flutter/material.dart';

import '../../app/theme/theme_controller.dart';

class AppSettingsSheet extends StatelessWidget {
  const AppSettingsSheet({
    super.key,
    required this.onOpenPermissions,
    required this.onOpenBackup,
  });

  final VoidCallback onOpenPermissions;
  final VoidCallback onOpenBackup;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onOpenPermissions,
    required VoidCallback onOpenBackup,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .86,
        child: AppSettingsSheet(
          onOpenPermissions: onOpenPermissions,
          onOpenBackup: onOpenBackup,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text('Aparência e ajustes', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Personalize o Fyno e gerencie os recursos do aplicativo.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text('Tema', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _ThemeOption(
            mode: ThemeMode.system,
            icon: Icons.brightness_auto_rounded,
            title: 'Usar tema do celular',
            subtitle: 'Acompanha automaticamente o sistema',
          ),
          const SizedBox(height: 8),
          _ThemeOption(
            mode: ThemeMode.light,
            icon: Icons.light_mode_rounded,
            title: 'Tema claro',
            subtitle: 'Visual claro e com alto contraste',
          ),
          const SizedBox(height: 8),
          _ThemeOption(
            mode: ThemeMode.dark,
            icon: Icons.dark_mode_rounded,
            title: 'Tema escuro',
            subtitle: 'Mais confortável em ambientes escuros',
          ),
          const SizedBox(height: 24),
          Text('Aplicativo', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _SettingsAction(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Permissões',
            subtitle: 'Câmera, notificações e acesso do Android',
            onTap: onOpenPermissions,
          ),
          const SizedBox(height: 8),
          _SettingsAction(
            icon: Icons.cloud_upload_rounded,
            title: 'Backup e restauração',
            subtitle: 'Proteja ou recupere seus dados',
            onTap: onOpenBackup,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_rounded, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Com uma conta Google conectada, seus dados financeiros e o tema também podem acompanhar você em outro celular.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final ThemeMode mode;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = ThemeController.instance.mode == mode;

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: .65)
          : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => ThemeController.instance.setMode(mode),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(selected),
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
