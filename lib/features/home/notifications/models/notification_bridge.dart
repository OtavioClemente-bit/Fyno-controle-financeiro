import 'package:flutter/services.dart';

class NotificationDiagnostics {
  const NotificationDiagnostics({
    required this.permissionEnabled,
    required this.captureEnabled,
    required this.listenerConnected,
    required this.lastConnectedAt,
    required this.lastSeenAt,
    required this.lastSeenPackage,
    required this.lastCapturedAt,
    required this.lastRejectionReason,
    required this.observedCount,
    required this.capturedCount,
  });

  const NotificationDiagnostics.empty()
    : permissionEnabled = false,
      captureEnabled = false,
      listenerConnected = false,
      lastConnectedAt = null,
      lastSeenAt = null,
      lastSeenPackage = '',
      lastCapturedAt = null,
      lastRejectionReason = '',
      observedCount = 0,
      capturedCount = 0;

  final bool permissionEnabled;
  final bool captureEnabled;
  final bool listenerConnected;
  final DateTime? lastConnectedAt;
  final DateTime? lastSeenAt;
  final String lastSeenPackage;
  final DateTime? lastCapturedAt;
  final String lastRejectionReason;
  final int observedCount;
  final int capturedCount;

  factory NotificationDiagnostics.fromMap(Map<Object?, Object?> map) {
    DateTime? date(Object? value) {
      final milliseconds = value is num
          ? value.toInt()
          : int.tryParse('$value');
      return milliseconds == null || milliseconds <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }

    int number(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;

    return NotificationDiagnostics(
      permissionEnabled: map['permission_enabled'] == true,
      captureEnabled: map['capture_enabled'] == true,
      listenerConnected: map['listener_connected'] == true,
      lastConnectedAt: date(map['last_connected_at_ms']),
      lastSeenAt: date(map['last_seen_at_ms']),
      lastSeenPackage: '${map['last_seen_package'] ?? ''}',
      lastCapturedAt: date(map['last_captured_at_ms']),
      lastRejectionReason: '${map['last_rejection_reason'] ?? ''}',
      observedCount: number(map['observed_count']),
      capturedCount: number(map['captured_count']),
    );
  }
}

/// Ponte nativa única para o acesso especial de notificações no Android.
///
/// O listener permanece bloqueado até que haja consentimento explícito e pelo
/// menos um banco selecionado. Em outras plataformas, os métodos falham de
/// forma segura e retornam `false`/lista vazia.
class NotificationBridge {
  NotificationBridge._();
  static final NotificationBridge instance = NotificationBridge._();

  static const MethodChannel _accessChannel = MethodChannel('notif_access');
  static const MethodChannel _bufferChannel = MethodChannel(
    'fyno/notification_buffer',
  );

  String? lastError;

  T _failed<T>(Object error, T fallback) {
    lastError = '$error';
    return fallback;
  }

  Future<bool> isNotificationListenerEnabled() async {
    try {
      return await _accessChannel.invokeMethod<bool>(
            'isNotificationListenerEnabled',
          ) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> openNotificationListenerSettings() async {
    try {
      final result = await _accessChannel.invokeMethod<bool>(
        'openNotificationListenerSettings',
      );
      return result ?? true;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> isCaptureEnabled() async {
    try {
      return await _accessChannel.invokeMethod<bool>('isCaptureEnabled') ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> setCaptureEnabled(bool enabled) async {
    try {
      return await _accessChannel.invokeMethod<bool>('setCaptureEnabled', {
            'enabled': enabled,
          }) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> setAllowedPackages(Set<String> packages) async {
    try {
      return await _bufferChannel.invokeMethod<bool>('setAllowedPackages', {
            'packages': packages.toList(growable: false),
          }) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<List<Map<String, dynamic>>> drainBufferedNotifications() async {
    try {
      final result = await _bufferChannel.invokeMethod<Object?>('drain');
      if (result is! List) return const [];
      return result
          .whereType<Map>()
          .map((map) => map.map((key, value) => MapEntry('$key', value)))
          .cast<Map<String, dynamic>>()
          .toList(growable: false);
    } catch (error) {
      return _failed(error, const []);
    }
  }

  Future<bool> clearBufferedNotifications() async {
    try {
      return await _bufferChannel.invokeMethod<bool>('clear') ?? false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<NotificationDiagnostics> getDiagnostics() async {
    try {
      final result = await _accessChannel.invokeMethod<Map<Object?, Object?>>(
        'getNotificationDiagnostics',
      );
      return result == null
          ? const NotificationDiagnostics.empty()
          : NotificationDiagnostics.fromMap(result);
    } catch (error) {
      return _failed(error, const NotificationDiagnostics.empty());
    }
  }

  Future<Set<String>> getInstalledPackages(Set<String> candidates) async {
    try {
      final result = await _accessChannel.invokeListMethod<String>(
        'getInstalledPackages',
        {'packages': candidates.toList(growable: false)},
      );
      return (result ?? const <String>[]).toSet();
    } catch (error) {
      return _failed(error, <String>{});
    }
  }

  Future<bool> requestRebind() async {
    try {
      return await _accessChannel.invokeMethod<bool>(
            'requestNotificationRebind',
          ) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> hasBackgroundStartupSettings() async {
    try {
      return await _accessChannel.invokeMethod<bool>(
            'hasBackgroundStartupSettings',
          ) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> openBackgroundStartupSettings() async {
    try {
      return await _accessChannel.invokeMethod<bool>(
            'openBackgroundStartupSettings',
          ) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> runSelfTest() async {
    try {
      return await _accessChannel.invokeMethod<bool>(
            'runNotificationSelfTest',
          ) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> scheduleReviewReminder({
    required int notificationId,
    required DateTime at,
    required String bankName,
    required double? amount,
  }) async {
    try {
      return await _accessChannel.invokeMethod<bool>('scheduleReviewReminder', {
            'notificationId': notificationId,
            'atMs': at.millisecondsSinceEpoch,
            'bankName': bankName,
            'amount': amount,
          }) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<bool> cancelReviewReminder(int notificationId) async {
    try {
      return await _accessChannel.invokeMethod<bool>('cancelReviewReminder', {
            'notificationId': notificationId,
          }) ??
          false;
    } catch (error) {
      return _failed(error, false);
    }
  }

  Future<int?> consumeLaunchedReminder() async {
    try {
      return await _accessChannel.invokeMethod<int>('consumeLaunchedReminder');
    } catch (error) {
      return _failed<int?>(error, null);
    }
  }
}
