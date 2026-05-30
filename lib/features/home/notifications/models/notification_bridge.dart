import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

/// Ponte (wrapper) para o plugin notification_listener_service.
///
/// Mantém uma API estável para o app:
/// - isNotificationListenerEnabled()
/// - openNotificationListenerSettings()
/// - start(...) / stop()
class NotificationBridge {
  NotificationBridge._();
  static final NotificationBridge instance = NotificationBridge._();

  StreamSubscription<ServiceNotificationEvent>? _sub;

  bool get isRunning => _sub != null;

  Future<bool> isNotificationListenerEnabled() async {
    try {
      return await NotificationListenerService.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  /// Abre a tela/permissão do Notification Listener (Android).
  Future<void> openNotificationListenerSettings() async {
    try {
      await NotificationListenerService.requestPermission();
    } catch (_) {
      // ignore
    }
  }

  /// Inicia a captura ao vivo.
  ///
  /// Se [allowedPackages] for informado, filtra somente esses pacotes.
  void start({
    Set<String>? allowedPackages,
    required FutureOr<void> Function(ServiceNotificationEvent event) onEvent,
  }) {
    if (_sub != null) return;

    _sub = NotificationListenerService.notificationsStream.listen(
      (event) async {
        try {
          final pkg = (event.packageName ?? '').toString();
          if (allowedPackages != null && allowedPackages.isNotEmpty) {
            if (!allowedPackages.contains(pkg)) return;
          }
          await onEvent(event);
        } catch (e, st) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('[NOTIF] onEvent error: $e\n$st');
          }
        }
      },
      onError: (e, st) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[NOTIF] stream error: $e\n$st');
        }
      },
    );
  }

  Future<void> stop() async {
    final s = _sub;
    _sub = null;
    await s?.cancel();
  }
}
