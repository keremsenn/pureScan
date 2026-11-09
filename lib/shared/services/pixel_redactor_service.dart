import 'dart:io';
import 'package:image/image.dart' as img;
import '../../core/constants/app_constants.dart';
import '../../core/security/privacy_logger.dart';
import '../../core/security/temp_file_manager.dart';
import '../../core/utils/coordinate_utils.dart';
import '../models/redaction_area.dart';
import '../models/scanned_page.dart';
import 'image_sanitizer.dart';

class PixelRedactorService {
  PixelRedactorService._();

  static Future<Map<String, File>> applyRedactionsToAllPages({
    required List<ScannedPage> pages,
    required Map<String, List<RedactionArea>> redactionsMap,
    required Directory sessionDir,
  }) async {
    PrivacyLogger.logInfo('PIXEL_REDACTION_BATCH_START');
    final cleanImagesMap = <String, File>{};

    for (final page in pages) {
      final areas = redactionsMap[page.id] ?? const [];
      cleanImagesMap[page.id] = await _redactSinglePage(
        page: page,
        areas: areas,
        sessionDir: sessionDir,
      );
    }

    PrivacyLogger.logInfo('PIXEL_REDACTION_BATCH_COMPLETE');
    return cleanImagesMap;
  }

  static img.Image redactImage(img.Image source, List<RedactionArea> areas) {
    final image = ImageSanitizer.flatten(source);
    final solidBlack = img.ColorRgb8(0, 0, 0);

    for (final area in areas) {
      final b = CoordinateUtils.toPixelBounds(
        normalizedRect: area.normalizedRect,
        imageWidth: image.width,
        imageHeight: image.height,
        securityMargin: AppConstants.redactionSecurityMarginPx,
      );

      img.fillRect(
        image,
        x1: b.left,
        y1: b.top,
        x2: b.right - 1,
        y2: b.bottom - 1,
        color: solidBlack,
        alphaBlend: false,
      );
    }
    return image;
  }

  static Future<File> _redactSinglePage({
    required ScannedPage page,
    required List<RedactionArea> areas,
    required Directory sessionDir,
  }) async {
    final bytes = await File(page.currentImagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      PrivacyLogger.logError('PIXEL_REDACT_DECODE_FAIL');
      throw Exception('Sayfa görüntüsü okunamadı.');
    }
    if (decoded.width != page.width || decoded.height != page.height) {
      throw Exception(
        'Sayfa geometrisi değişmiş. Lütfen alanları yeniden seçin.',
      );
    }

    final redacted = redactImage(decoded, areas);
    final cleanPath = TempFileManager.getPageImagePath(
      sessionDir,
      '${page.id}_clean',
      'png',
    );
    return ImageSanitizer.writePng(redacted, cleanPath);
  }
}
