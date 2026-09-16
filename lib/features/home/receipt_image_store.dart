import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Mantém comprovantes fora do cache temporário da câmera/galeria.
class ReceiptImageStore {
  ReceiptImageStore._();

  static const _directoryName = 'fyno_receipts';

  static Future<String?> persist(String? sourcePath) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final directory = await _directory();
    if (p.isWithin(directory.path, source.path)) return source.path;

    final extension = _safeExtension(source.path);
    final name = 'receipt_${DateTime.now().microsecondsSinceEpoch}$extension';
    final destination = File(p.join(directory.path, name));
    await source.copy(destination.path);
    return destination.path;
  }

  static Future<void> deleteIfManaged(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    final directory = await _directory();
    if (!p.isWithin(directory.path, path)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, _directoryName));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static String _safeExtension(String path) {
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
}
