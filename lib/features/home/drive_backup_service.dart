import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:controle_financeiro/app/theme/theme_controller.dart';
import 'package:controle_financeiro/core/db/app_db.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class CloudBackupInfo {
  const CloudBackupInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    this.transactionCount,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;
  final int? transactionCount;
}

class BackupResult {
  const BackupResult({
    required this.backup,
    required this.imagesIncluded,
    required this.imagesSkipped,
  });

  final CloudBackupInfo backup;
  final int imagesIncluded;
  final int imagesSkipped;
}

class RestoreResult {
  const RestoreResult({
    required this.transactionCount,
    required this.imagesRestored,
  });

  final int transactionCount;
  final int imagesRestored;
}

class DriveBackupException implements Exception {
  const DriveBackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Login Google e backups privados no `appDataFolder` do Google Drive.
///
/// A pasta não aparece para outros aplicativos nem na interface normal do
/// Drive. O único escopo solicitado é o específico para dados deste app.
class DriveBackupService extends ChangeNotifier {
  DriveBackupService._();

  static final DriveBackupService instance = DriveBackupService._();

  static const scopes = <String>[drive.DriveApi.driveAppdataScope];
  static const _format = 'fyno-cloud-backup';
  static const _formatVersion = 1;
  static const _prefix = 'fyno_backup_';
  static const _maxBackups = 3;
  static const _maxArchiveBytes = 200 * 1024 * 1024;
  static const _maxReceiptBytes = 20 * 1024 * 1024;
  static const _maxAllReceiptsBytes = 120 * 1024 * 1024;
  static const _lastBackupKey = 'google_drive_last_backup_ms';

  // No Android, a configuração registrada pelo pacote+SHA é usada. Os
  // defines permitem fornecer IDs explicitamente em outras plataformas.
  static const _clientId = String.fromEnvironment('FYNO_GOOGLE_CLIENT_ID');
  static const _serverClientId = String.fromEnvironment(
    'FYNO_GOOGLE_SERVER_CLIENT_ID',
  );

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  GoogleSignInAccount? _account;
  bool _initialized = false;
  bool _initializing = false;
  String? _configurationError;
  DateTime? _lastBackupAt;

  GoogleSignInAccount? get account => _account;
  bool get isConnected => _account != null;
  bool get isInitializing => _initializing;
  String? get configurationError => _configurationError;
  DateTime? get lastBackupAt => _lastBackupAt;

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getInt(_lastBackupKey);
      _lastBackupAt = saved == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(saved);

      await _signIn.initialize(
        clientId: _clientId.isEmpty ? null : _clientId,
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
      _authSubscription = _signIn.authenticationEvents.listen(
        _handleAuthEvent,
        onError: (Object error) {
          _configurationError = _friendlyGoogleError(error);
          notifyListeners();
        },
      );
      _initialized = true;

      final lightweight = _signIn.attemptLightweightAuthentication();
      if (lightweight != null) _account = await lightweight;
      _configurationError = null;
    } catch (error) {
      _configurationError = _friendlyGoogleError(error);
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  void _handleAuthEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _account = event.user;
        _configurationError = null;
      case GoogleSignInAuthenticationEventSignOut():
        _account = null;
    }
    notifyListeners();
  }

  Future<void> connect() async {
    await initialize();
    try {
      final user = await _signIn.authenticate(scopeHint: scopes);
      _account = user;
      await user.authorizationClient.authorizationForScopes(scopes) ??
          await user.authorizationClient.authorizeScopes(scopes);
      _configurationError = null;
      notifyListeners();
    } catch (error) {
      throw DriveBackupException(_friendlyGoogleError(error));
    }
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    _account = null;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _signIn.disconnect();
    _account = null;
    notifyListeners();
  }

  Future<List<CloudBackupInfo>> listBackups() async {
    return _withDrive((api) async {
      final response = await api.files.list(
        spaces: 'appDataFolder',
        q: "trashed = false and name contains '$_prefix'",
        orderBy: 'modifiedTime desc',
        pageSize: 20,
        $fields: 'files(id,name,createdTime,modifiedTime,size,appProperties)',
      );
      return (response.files ?? const <drive.File>[])
          .where((file) => file.id != null)
          .map(_backupFromDriveFile)
          .toList(growable: false);
    });
  }

  Future<BackupResult> backupNow() async {
    final package = await _createBackupPackage();
    try {
      final saved = await _withDrive((api) async {
        final metadata = drive.File(
          name: package.name,
          parents: const <String>['appDataFolder'],
          mimeType: 'application/zip',
          appProperties: <String, String>{
            'fynoFormat': _format,
            'formatVersion': '$_formatVersion',
            'transactions': '${package.transactionCount}',
          },
        );
        final uploaded = await api.files.create(
          metadata,
          uploadMedia: drive.Media(
            package.file.openRead(),
            await package.file.length(),
            contentType: 'application/zip',
          ),
          $fields: 'id,name,createdTime,modifiedTime,size,appProperties',
        );
        await _removeOldBackups(api);
        return _backupFromDriveFile(uploaded);
      }, interactiveAuthorization: true);

      final now = DateTime.now();
      _lastBackupAt = now;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_lastBackupKey, now.millisecondsSinceEpoch);
      notifyListeners();
      return BackupResult(
        backup: saved,
        imagesIncluded: package.imagesIncluded,
        imagesSkipped: package.imagesSkipped,
      );
    } finally {
      if (await package.file.exists()) await package.file.delete();
    }
  }

  Future<RestoreResult> restore(CloudBackupInfo backup) async {
    if (backup.sizeBytes > _maxArchiveBytes) {
      throw const DriveBackupException(
        'Esta cópia é grande demais para ser restaurada com segurança.',
      );
    }

    final bytes = await _withDrive((api) async {
      final response = await api.files.get(
        backup.id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      final media = response as drive.Media;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in media.stream) {
        received += chunk.length;
        if (received > _maxArchiveBytes) {
          throw const DriveBackupException(
            'A cópia excede o limite seguro de restauração.',
          );
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }, interactiveAuthorization: true);

    return _restorePackage(bytes);
  }

  Future<void> deleteAllBackups() async {
    await _withDrive((api) async {
      final response = await api.files.list(
        spaces: 'appDataFolder',
        q: "trashed = false and name contains '$_prefix'",
        pageSize: 100,
        $fields: 'files(id)',
      );
      for (final file in response.files ?? const <drive.File>[]) {
        if (file.id != null) await api.files.delete(file.id!);
      }
    }, interactiveAuthorization: true);
    _lastBackupAt = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lastBackupKey);
    notifyListeners();
  }

  Future<T> _withDrive<T>(
    Future<T> Function(drive.DriveApi api) action, {
    bool interactiveAuthorization = false,
  }) async {
    await initialize();
    final user = _account;
    if (user == null) {
      throw const DriveBackupException('Conecte sua conta Google primeiro.');
    }

    try {
      var authorization = await user.authorizationClient.authorizationForScopes(
        scopes,
      );
      if (authorization == null && interactiveAuthorization) {
        authorization = await user.authorizationClient.authorizeScopes(scopes);
      }
      if (authorization == null) {
        throw const DriveBackupException(
          'Autorize o Fyno a salvar a cópia privada no Google Drive.',
        );
      }
      final client = authorization.authClient(scopes: scopes);
      try {
        return await action(drive.DriveApi(client));
      } finally {
        client.close();
      }
    } on DriveBackupException {
      rethrow;
    } catch (error) {
      throw DriveBackupException(_friendlyDriveError(error));
    }
  }

  Future<_BackupPackage> _createBackupPackage() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const DriveBackupException(
        'O backup em nuvem está disponível no aplicativo para celular.',
      );
    }

    final temp = await getTemporaryDirectory();
    final liveFile = File(await AppDb.filePath);
    if (!await liveFile.exists()) await AppDb.instance;
    final liveDatabase = await AppDb.instance;
    await liveDatabase.rawQuery('PRAGMA wal_checkpoint(FULL)');

    final now = DateTime.now();
    final stamp = _stamp(now);
    final snapshot = File(p.join(temp.path, 'fyno_snapshot_$stamp.db'));
    final output = File(p.join(temp.path, '$_prefix$stamp.fynobackup'));
    await liveFile.copy(snapshot.path);

    final archive = Archive();
    var imagesIncluded = 0;
    var imagesSkipped = 0;
    var receiptBytes = 0;
    var transactionCount = 0;
    var databaseVersion = 0;
    final counts = <String, int>{};

    final snapshotDb = await openDatabase(snapshot.path, singleInstance: false);
    try {
      await snapshotDb.delete('pending_notifications');
      await snapshotDb.delete('selected_notification_apps');

      const backedUpTables = <String>[
        'transactions',
        'receipt_items',
        'vehicles',
        'fuel_logs',
        'categories',
      ];
      for (final table in backedUpTables) {
        final result = await snapshotDb.rawQuery(
          'SELECT COUNT(*) AS total FROM $table',
        );
        counts[table] = (result.first['total'] as num?)?.toInt() ?? 0;
      }
      transactionCount = counts['transactions'] ?? 0;
      databaseVersion = await snapshotDb.getVersion();

      final receipts = await snapshotDb.query(
        'transactions',
        columns: const <String>['id', 'receipt_image_path'],
        where: 'receipt_image_path IS NOT NULL',
      );
      await snapshotDb.update('transactions', const <String, Object?>{
        'receipt_image_path': null,
      }, where: 'receipt_image_path IS NOT NULL');

      for (final row in receipts) {
        final id = (row['id'] as num?)?.toInt();
        final sourcePath = row['receipt_image_path'] as String?;
        if (id == null || sourcePath == null) continue;
        final source = File(sourcePath);
        if (!await source.exists()) {
          imagesSkipped++;
          continue;
        }
        final length = await source.length();
        if (length > _maxReceiptBytes ||
            receiptBytes + length > _maxAllReceiptsBytes) {
          imagesSkipped++;
          continue;
        }
        final extension = _safeImageExtension(sourcePath);
        final archiveName = 'receipts/$id$extension';
        archive.add(ArchiveFile.bytes(archiveName, await source.readAsBytes()));
        await snapshotDb.update(
          'transactions',
          <String, Object?>{'receipt_image_path': 'fyno-receipt:$archiveName'},
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        receiptBytes += length;
        imagesIncluded++;
      }

      await snapshotDb.execute('VACUUM');
    } finally {
      await snapshotDb.close();
    }

    final manifest = <String, Object?>{
      'format': _format,
      'formatVersion': _formatVersion,
      'createdAt': now.toUtc().toIso8601String(),
      'databaseVersion': databaseVersion,
      'appVersion': '1.10.0',
      'counts': counts,
      'imagesIncluded': imagesIncluded,
      'imagesSkipped': imagesSkipped,
      'preferences': <String, Object?>{
        'themeMode': ThemeController.instance.mode.name,
      },
      'privacy': <String, Object?>{
        'notificationsIncluded': false,
        'selectedNotificationAppsIncluded': false,
      },
    };
    archive.add(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    archive.add(ArchiveFile.bytes('database.db', await snapshot.readAsBytes()));
    final encoded = ZipEncoder().encodeBytes(archive);
    if (encoded.length > _maxArchiveBytes) {
      throw const DriveBackupException(
        'A cópia ficou grande demais. Remova algumas imagens de comprovantes e tente novamente.',
      );
    }
    await output.writeAsBytes(encoded, flush: true);
    if (await snapshot.exists()) await snapshot.delete();

    return _BackupPackage(
      file: output,
      name: '$_prefix$stamp.fynobackup',
      transactionCount: transactionCount,
      imagesIncluded: imagesIncluded,
      imagesSkipped: imagesSkipped,
    );
  }

  Future<RestoreResult> _restorePackage(Uint8List bytes) async {
    final temp = await getTemporaryDirectory();
    final stamp = _stamp(DateTime.now());
    final candidate = File(p.join(temp.path, 'fyno_restore_$stamp.db'));
    final rollback = File(p.join(temp.path, 'fyno_rollback_$stamp.db'));
    final createdImages = <File>[];

    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final manifestEntry = archive.find('manifest.json');
      final databaseEntry = archive.find('database.db');
      if (manifestEntry == null || databaseEntry == null) {
        throw const DriveBackupException('Arquivo de backup incompleto.');
      }

      final manifest = jsonDecode(utf8.decode(manifestEntry.content));
      if (manifest is! Map<String, dynamic> ||
          manifest['format'] != _format ||
          manifest['formatVersion'] != _formatVersion) {
        throw const DriveBackupException(
          'Este arquivo não é uma cópia compatível do Fyno.',
        );
      }
      await candidate.writeAsBytes(databaseEntry.content, flush: true);

      final candidateDb = await openDatabase(
        candidate.path,
        singleInstance: false,
      );
      var imagesRestored = 0;
      var transactionCount = 0;
      try {
        final integrity = await candidateDb.rawQuery('PRAGMA integrity_check');
        if (integrity.isEmpty || integrity.first.values.first != 'ok') {
          throw const DriveBackupException(
            'A cópia está corrompida e não foi aplicada.',
          );
        }
        final tables = await candidateDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );
        final names = tables.map((row) => row['name']).toSet();
        if (!names.containsAll(<String>{
          'transactions',
          'receipt_items',
          'vehicles',
          'fuel_logs',
          'categories',
        })) {
          throw const DriveBackupException(
            'A cópia não contém todas as tabelas obrigatórias.',
          );
        }

        final documents = await getApplicationDocumentsDirectory();
        final receiptDirectory = Directory(
          p.join(documents.path, 'fyno_receipts'),
        );
        await receiptDirectory.create(recursive: true);
        final rows = await candidateDb.query(
          'transactions',
          columns: const <String>['id', 'receipt_image_path'],
          where: "receipt_image_path LIKE 'fyno-receipt:%'",
        );
        for (final row in rows) {
          final id = (row['id'] as num).toInt();
          final marker = row['receipt_image_path'] as String;
          final archiveName = marker.substring('fyno-receipt:'.length);
          final imageEntry = archive.find(archiveName);
          if (imageEntry == null || !imageEntry.isFile) {
            await candidateDb.update(
              'transactions',
              const <String, Object?>{'receipt_image_path': null},
              where: 'id = ?',
              whereArgs: <Object?>[id],
            );
            continue;
          }
          final extension = p.extension(archiveName).toLowerCase();
          final image = File(
            p.join(receiptDirectory.path, 'restored_${stamp}_$id$extension'),
          );
          await image.writeAsBytes(imageEntry.content, flush: true);
          createdImages.add(image);
          await candidateDb.update(
            'transactions',
            <String, Object?>{'receipt_image_path': image.path},
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
          imagesRestored++;
        }
        final count = await candidateDb.rawQuery(
          'SELECT COUNT(*) AS total FROM transactions',
        );
        transactionCount = (count.first['total'] as num?)?.toInt() ?? 0;
      } finally {
        await candidateDb.close();
      }

      final liveFile = File(await AppDb.filePath);
      final liveDb = await AppDb.instance;
      await liveDb.rawQuery('PRAGMA wal_checkpoint(FULL)');
      await AppDb.close();
      if (await liveFile.exists()) await liveFile.copy(rollback.path);
      await _deleteSqliteSidecars(liveFile.path);

      try {
        await candidate.copy(liveFile.path);
        final restoredDb = await AppDb.instance;
        final check = await restoredDb.rawQuery('PRAGMA integrity_check');
        if (check.isEmpty || check.first.values.first != 'ok') {
          throw const DriveBackupException(
            'Não foi possível validar os dados restaurados.',
          );
        }
      } catch (error) {
        await AppDb.close();
        if (await rollback.exists()) await rollback.copy(liveFile.path);
        await AppDb.instance;
        rethrow;
      }

      final preferences = manifest['preferences'];
      if (preferences is Map<String, dynamic>) {
        final themeName = preferences['themeMode'];
        for (final mode in ThemeMode.values) {
          if (mode.name == themeName) {
            await ThemeController.instance.setMode(mode);
            break;
          }
        }
      }
      return RestoreResult(
        transactionCount: transactionCount,
        imagesRestored: imagesRestored,
      );
    } on DriveBackupException {
      for (final image in createdImages) {
        if (await image.exists()) await image.delete();
      }
      rethrow;
    } catch (error) {
      for (final image in createdImages) {
        if (await image.exists()) await image.delete();
      }
      throw DriveBackupException('Não foi possível restaurar: $error');
    } finally {
      if (await candidate.exists()) await candidate.delete();
      if (await rollback.exists()) await rollback.delete();
    }
  }

  Future<void> _removeOldBackups(drive.DriveApi api) async {
    final response = await api.files.list(
      spaces: 'appDataFolder',
      q: "trashed = false and name contains '$_prefix'",
      orderBy: 'modifiedTime desc',
      pageSize: 20,
      $fields: 'files(id,modifiedTime)',
    );
    final files = response.files ?? const <drive.File>[];
    for (final old in files.skip(_maxBackups)) {
      if (old.id != null) await api.files.delete(old.id!);
    }
  }

  CloudBackupInfo _backupFromDriveFile(drive.File file) {
    final properties = file.appProperties ?? const <String, String?>{};
    return CloudBackupInfo(
      id: file.id!,
      name: file.name ?? 'Cópia do Fyno',
      createdAt:
          file.modifiedTime ?? file.createdTime ?? DateTime.now().toUtc(),
      sizeBytes: int.tryParse(file.size ?? '') ?? 0,
      transactionCount: int.tryParse(properties['transactions'] ?? ''),
    );
  }

  static Future<void> _deleteSqliteSidecars(String databasePath) async {
    for (final suffix in const <String>['-wal', '-shm', '-journal']) {
      final file = File('$databasePath$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  static String _safeImageExtension(String path) {
    final extension = p.extension(path).toLowerCase();
    return const <String>{
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
          '.heic',
        }.contains(extension)
        ? extension
        : '.jpg';
  }

  static String _stamp(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}${two(date.month)}${two(date.day)}_'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}';
  }

  static String _friendlyGoogleError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('canceled') || text.contains('cancelled')) {
      return 'A conexão com a conta Google foi cancelada.';
    }
    if (text.contains('network')) {
      return 'Sem conexão com o Google. Confira sua internet e tente novamente.';
    }
    if (text.contains('configuration') ||
        text.contains('developer_error') ||
        text.contains('10:')) {
      return 'O acesso Google desta versão ainda precisa ser autorizado para a assinatura do aplicativo.';
    }
    return 'Não foi possível conectar à conta Google. Tente novamente.';
  }

  static String _friendlyDriveError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('401') || text.contains('unauthorized')) {
      return 'Sua sessão Google expirou. Desconecte e conecte a conta novamente.';
    }
    if (text.contains('403')) {
      return 'O Google Drive recusou o acesso. Confirme a autorização do Fyno.';
    }
    if (text.contains('network') || text.contains('socket')) {
      return 'A internet falhou durante a sincronização. Seus dados locais continuam seguros.';
    }
    return 'O Google Drive não respondeu como esperado. Tente novamente em instantes.';
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

class _BackupPackage {
  const _BackupPackage({
    required this.file,
    required this.name,
    required this.transactionCount,
    required this.imagesIncluded,
    required this.imagesSkipped,
  });

  final File file;
  final String name;
  final int transactionCount;
  final int imagesIncluded;
  final int imagesSkipped;
}
