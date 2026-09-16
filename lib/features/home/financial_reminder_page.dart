import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notifications/models/notification_bridge.dart';

class FinancialReminderPage extends StatefulWidget {
  const FinancialReminderPage({super.key});
  static const notificationId = 900000;

  @override
  State<FinancialReminderPage> createState() => _FinancialReminderPageState();
}

class _FinancialReminderPageState extends State<FinancialReminderPage> {
  static const _timeKey = 'financial_reminder_at_ms';
  DateTime? _scheduledAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = (await SharedPreferences.getInstance()).getInt(_timeKey);
    final date = value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value);
    if (mounted) {
      setState(
        () =>
            _scheduledAt = date?.isAfter(DateTime.now()) == true ? date : null,
      );
    }
  }

  DateTime _nextAt(int hour, {int days = 0}) {
    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day + days, hour);
    if (!date.isAfter(now)) date = date.add(const Duration(days: 1));
    return date;
  }

  DateTime _nextSaturday() {
    final now = DateTime.now();
    var days = DateTime.saturday - now.weekday;
    if (days < 0) days += 7;
    var date = DateTime(now.year, now.month, now.day + days, 10);
    if (!date.isAfter(now)) date = date.add(const Duration(days: 7));
    return date;
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (time != null) {
      await _schedule(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    }
  }

  Future<void> _schedule(DateTime at) async {
    if (!at.isAfter(DateTime.now())) return;
    setState(() => _saving = true);
    var permissionGranted = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      permissionGranted = (await Permission.notification.request()).isGranted;
    }
    final scheduled = await NotificationBridge.instance.scheduleReviewReminder(
      notificationId: FinancialReminderPage.notificationId,
      at: at,
      bankName: '',
      amount: null,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeKey, at.millisecondsSinceEpoch);
    if (!mounted) return;
    setState(() {
      _scheduledAt = at;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          permissionGranted && scheduled
              ? 'Lembrete financeiro agendado.'
              : 'Horário salvo. Ative as notificações para receber o aviso.',
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    await NotificationBridge.instance.cancelReviewReminder(
      FinancialReminderPage.notificationId,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_timeKey);
    if (mounted) setState(() => _scheduledAt = null);
  }

  String _format(DateTime date) {
    const weekdays = [
      'segunda',
      'terça',
      'quarta',
      'quinta',
      'sexta',
      'sábado',
      'domingo',
    ];
    final minute = date.minute.toString().padLeft(2, '0');
    return '${weekdays[date.weekday - 1]}, ${date.day}/${date.month} às ${date.hour}:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes financeiros')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_active_rounded, color: cs.onPrimary),
                const SizedBox(height: 18),
                Text(
                  'Um pequeno hábito faz diferença',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'O Fyno lembra você de registrar gastos, conferir cartões e deixar suas contas em dia.',
                  style: TextStyle(color: cs.onPrimary.withValues(alpha: .86)),
                ),
              ],
            ),
          ),
          if (_scheduledAt != null) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: cs.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.check_circle_rounded),
                title: const Text(
                  'Próximo lembrete',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(_format(_scheduledAt!)),
                trailing: IconButton(
                  tooltip: 'Cancelar lembrete',
                  onPressed: _cancel,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Quando você quer ser lembrado?',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _ReminderOption(
            Icons.nightlight_round,
            'Hoje à noite',
            _format(_nextAt(20)),
            _saving ? null : () => _schedule(_nextAt(20)),
          ),
          _ReminderOption(
            Icons.wb_sunny_outlined,
            'Amanhã cedo',
            _format(_nextAt(9, days: 1)),
            _saving ? null : () => _schedule(_nextAt(9, days: 1)),
          ),
          _ReminderOption(
            Icons.calendar_view_week_rounded,
            'No fim de semana',
            _format(_nextSaturday()),
            _saving ? null : () => _schedule(_nextSaturday()),
          ),
          _ReminderOption(
            Icons.edit_calendar_rounded,
            'Escolher data e horário',
            'Defina o melhor momento para você',
            _saving ? null : _pickCustom,
          ),
        ],
      ),
    );
  }
}

class _ReminderOption extends StatelessWidget {
  const _ReminderOption(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    child: ListTile(
      minTileHeight: 72,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
