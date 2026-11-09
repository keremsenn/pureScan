import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../core/security/privacy_logger.dart';
import '../../core/security/temp_file_manager.dart';
import '../../core/utils/file_utils.dart';
import '../models/verification_report.dart';

enum ShareOutcome { shared, dismissed, unknown }

class ShareGuardService {
  ShareGuardService._();

  static Future<File> _verifiedFile(VerificationReport report) async {
    if (!report.isPassed) {
      PrivacyLogger.logError('SHARE_BLOCKED_UNVERIFIED');
      throw const ShareBlockedException(
        'Dosya kontrol edilemedi, paylaşım yapılmadı.',
      );
    }
    final file = File(report.finalPdfPath);
    if (!await file.exists()) {
      throw const ShareBlockedException(
        'Doğrulanan dosya bulunamadı, paylaşım yapılmadı.',
      );
    }
    if (await FileUtils.computeSha256(file) != report.sha256Digest) {
      PrivacyLogger.logError('SHARE_HASH_MISMATCH');
      throw const ShareBlockedException(
        'Dosya doğrulamadan sonra değişmiş. Paylaşım engellendi.',
      );
    }
    return file;
  }

  static Future<ShareOutcome> shareVerifiedPdf({
    required VerificationReport report,
  }) async {
    final file = await _verifiedFile(report);

    final shareDir = await TempFileManager.getShareDirectory();
    final copy = await file.copy(p.join(shareDir.path, p.basename(file.path)));
    if (await FileUtils.computeSha256(copy) != report.sha256Digest) {
      throw const ShareBlockedException('Paylaşım kopyası doğrulanamadı.');
    }

    PrivacyLogger.logInfo('SHARE_INITIATED');
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(copy.path, mimeType: 'application/pdf')]),
    );
    return switch (result.status) {
      ShareResultStatus.success => ShareOutcome.shared,
      ShareResultStatus.dismissed => ShareOutcome.dismissed,
      _ => ShareOutcome.unknown,
    };
  }

  static Future<bool> saveVerifiedPdf({
    required VerificationReport report,
  }) async {
    final file = await _verifiedFile(report);
    final bytes = await file.readAsBytes();
    if (FileUtils.sha256OfBytes(bytes) != report.sha256Digest) {
      throw const ShareBlockedException('Dosya doğrulanamadı, kaydedilmedi.');
    }
    final savedPath = await FilePicker.saveFile(
      dialogTitle: 'Temiz PDF\'yi kaydet',
      fileName: p.basename(file.path),
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    PrivacyLogger.logInfo(savedPath == null ? 'SAVE_CANCELLED' : 'SAVE_DONE');
    return savedPath != null;
  }
}

class ShareBlockedException implements Exception {
  final String message;
  const ShareBlockedException(this.message);
  @override
  String toString() => message;
}
