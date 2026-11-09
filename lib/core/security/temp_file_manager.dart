import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'privacy_logger.dart';

class TempFileManager {
  TempFileManager._();

  static const String _sessionDirPrefix = 'pure_scan_session_';
  static const String shareDirName = 'pure_scan_share';
  static const Uuid _uuid = Uuid();

  static const List<String> _pluginTempDirs = ['file_picker', 'share_plus'];
  static final RegExp _pluginTempFile = RegExp(
    r'^(CAP|image_picker|scaled_|REC)',
    caseSensitive: false,
  );

  static Future<Directory> createSessionDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final sessionDir = Directory(
      p.join(tempDir.path, '$_sessionDirPrefix${_uuid.v4()}'),
    );
    await sessionDir.create(recursive: true);
    PrivacyLogger.logInfo('SESSION_DIR_CREATED');
    return sessionDir;
  }

  static Future<List<Directory>> _privateTempRoots() async {
    final roots = <String>{};
    try {
      roots.add((await getTemporaryDirectory()).path);
    } catch (_) {}
    try {
      roots.add(Directory.systemTemp.path);
    } catch (_) {}
    return roots.map(Directory.new).toList();
  }

  static Future<void> performStartupCleanup() async {
    for (final root in await _privateTempRoots()) {
      try {
        if (!await root.exists()) continue;
        await for (final entity in root.list(followLinks: false)) {
          final name = p.basename(entity.path);
          final shouldDelete = entity is Directory
              ? (name.startsWith(_sessionDirPrefix) ||
                    name == shareDirName ||
                    _pluginTempDirs.contains(name))
              : _pluginTempFile.hasMatch(name);
          if (!shouldDelete) continue;
          try {
            await entity.delete(recursive: true);
          } catch (e) {
            PrivacyLogger.logError('CLEANUP_DELETE_FAILED', e);
          }
        }
      } catch (e) {
        PrivacyLogger.logError('STARTUP_CLEANUP_FAILED', e);
      }
    }
    PrivacyLogger.logInfo('STARTUP_CLEANUP_DONE');
  }

  static Future<void> deleteSessionDirectory(Directory sessionDir) async {
    try {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
        PrivacyLogger.logInfo('SESSION_DIR_PURGED');
      }
    } catch (e) {
      PrivacyLogger.logError('SESSION_PURGE_FAILED', e);
    }
  }

  static Future<void> deleteIfPrivateTemp(String path) async {
    try {
      final normalized = p.normalize(File(path).absolute.path);
      for (final root in await _privateTempRoots()) {
        if (p.isWithin(p.normalize(root.absolute.path), normalized)) {
          final f = File(normalized);
          if (await f.exists()) await f.delete();
          return;
        }
      }
    } catch (e) {
      PrivacyLogger.logError('TEMP_COPY_DELETE_FAILED', e);
    }
  }

  static String newPageImagePath(Directory sessionDir, String pageId) {
    return p.join(
      sessionDir.path,
      'page_${pageId}_${_uuid.v4().substring(0, 8)}.png',
    );
  }

  static String getPageImagePath(
    Directory sessionDir,
    String pageId, [
    String extension = 'png',
  ]) {
    return p.join(sessionDir.path, 'page_$pageId.$extension');
  }

  static String getPartialPdfPath(Directory sessionDir) {
    return p.join(sessionDir.path, 'output_${_uuid.v4()}.pdf.part');
  }

  static Future<String> getVerifiedPdfPath(
    Directory sessionDir,
    String fileName,
  ) async {
    final outDir = Directory(p.join(sessionDir.path, 'verified'));
    await outDir.create(recursive: true);
    return p.join(outDir.path, fileName);
  }

  static Future<Directory> getShareDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, shareDirName, _uuid.v4()));
    await dir.create(recursive: true);
    return dir;
  }
}
