import 'dart:io';
import 'package:pdfx/pdfx.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/security/privacy_logger.dart';
import '../../core/security/temp_file_manager.dart';
import '../models/scanned_page.dart';
import 'image_sanitizer.dart';

class PdfRasterizerService {
  PdfRasterizerService._();

  static const Uuid _uuid = Uuid();

  static Future<PdfDocument> open(File pdfFile, {String? password}) async {
    try {
      return await PdfDocument.openFile(pdfFile.path, password: password);
    } catch (e) {
      PrivacyLogger.logError('PDF_OPEN_FAILED', e);
      throw PdfOpenException(
        needsPassword: password == null,
        message: password == null
            ? 'PDF açılamadı. Dosya şifreli, bozuk veya desteklenmeyen biçimde olabilir.'
            : 'PDF şifre ile de açılamadı. Şifre yanlış veya dosya desteklenmiyor.',
      );
    }
  }

  static Future<List<ScannedPage>> rasterizePdf({
    required PdfDocument doc,
    required Directory sessionDir,
    double dpi = AppConstants.defaultRenderDpi,
    void Function(int done, int total)? onProgress,
  }) async {
    PrivacyLogger.logInfo('PDF_RASTERIZATION_START');
    final pagesList = <ScannedPage>[];
    final pageCount = doc.pagesCount;

    if (pageCount == 0) {
      throw const PdfOpenException(message: 'PDF dosyasında sayfa bulunamadı.');
    }
    if (pageCount > AppConstants.maxPages) {
      throw PdfOpenException(
        message:
            'Belge $pageCount sayfa. Bu sürüm en fazla ${AppConstants.maxPages} sayfa destekler.',
      );
    }

    for (int i = 1; i <= pageCount; i++) {
      final page = await doc.getPage(i);
      try {
        final scale = dpi / 72.0;
        final pageImage = await page.render(
          width: (page.width * scale).roundToDouble(),
          height: (page.height * scale).roundToDouble(),
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        if (pageImage == null) {
          throw PdfOpenException(
            message: 'Sayfa $i görüntüye dönüştürülemedi.',
          );
        }

        final clean = ImageSanitizer.decodeAndFlatten(pageImage.bytes);
        final pageId = _uuid.v4();
        final targetPath = TempFileManager.newPageImagePath(sessionDir, pageId);
        await ImageSanitizer.writePng(clean, targetPath);

        pagesList.add(
          ScannedPage(
            id: pageId,
            originalImagePath: targetPath,
            currentImagePath: targetPath,
            width: clean.width,
            height: clean.height,
            pageIndex: i - 1,
            sourceDpi: dpi,
          ),
        );
      } finally {
        await page.close();
      }
      onProgress?.call(i, pageCount);
    }

    if (pagesList.length != pageCount) {
      throw const PdfOpenException(
        message: 'Bazı sayfalar okunamadı; işlem durduruldu.',
      );
    }
    PrivacyLogger.logInfo('PDF_RASTERIZATION_COMPLETE');
    return pagesList;
  }
}

class PdfOpenException implements Exception {
  final String message;
  final bool needsPassword;
  const PdfOpenException({required this.message, this.needsPassword = false});
  @override
  String toString() => message;
}
