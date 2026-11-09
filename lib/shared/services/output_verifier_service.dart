import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart';
import '../../core/security/privacy_logger.dart';
import '../../core/utils/coordinate_utils.dart';
import '../../core/utils/file_utils.dart';
import '../models/redaction_area.dart';
import '../models/scanned_page.dart';
import '../models/verification_report.dart';
import 'pdf_structure_inspector.dart';

class OutputVerifierService {
  OutputVerifierService._();

  static const double _orderCheckTolerance = 14.0;

  static Future<VerificationReport> verifyOutputPdf({
    required File generatedPdfFile,
    required List<ScannedPage> expectedPages,
    required Map<String, List<RedactionArea>> redactionsMap,
    required Map<String, File> cleanImagesMap,
  }) async {
    PrivacyLogger.logInfo('OUTPUT_VERIFICATION_START');
    final path = generatedPdfFile.path;

    if (!await generatedPdfFile.exists()) {
      return _fail(path, 'Oluşturulan PDF dosyası diskte bulunamadı.');
    }

    final pdfBytes = await generatedPdfFile.readAsBytes();
    final fileSize = pdfBytes.length;
    final sha256Digest = FileUtils.sha256OfBytes(pdfBytes);

    final inspection = PdfStructureInspector.inspect(pdfBytes);
    if (!inspection.isClean) {
      return _fail(
        path,
        inspection.problems.first,
        sha256: sha256Digest,
        fileSize: fileSize,
      );
    }
    if (inspection.pageObjectCount != expectedPages.length) {
      return _fail(
        path,
        'Dosya yapısındaki sayfa sayısı beklenenle eşleşmiyor.',
        sha256: sha256Digest,
        fileSize: fileSize,
      );
    }
    if (inspection.imageObjectCount != expectedPages.length) {
      return _fail(
        path,
        'Dosyada beklenmeyen veya gizli görüntü nesnesi var.',
        sha256: sha256Digest,
        fileSize: fileSize,
      );
    }

    final embedded = PdfStructureInspector.embeddedImageDigests(pdfBytes);
    final unmatched = embedded.map((e) => e.digest).toList();
    var totalAreasVerified = 0;
    for (var i = 0; i < expectedPages.length; i++) {
      final expected = expectedPages[i];
      final cleanFile = cleanImagesMap[expected.id];
      final clean = cleanFile == null
          ? null
          : img.decodePng(await cleanFile.readAsBytes());
      if (clean == null) {
        return _fail(
          path,
          'Sayfa ${i + 1} için temiz görüntü bulunamadı.',
          sha256: sha256Digest,
          fileSize: fileSize,
        );
      }
      final areas = redactionsMap[expected.id] ?? const <RedactionArea>[];
      for (final area in areas) {
        if (!_isAreaSolidBlack(clean, area, inset: 0)) {
          PrivacyLogger.logError('REDACTED_PIXEL_NOT_BLACK');
          return _fail(
            path,
            'Sayfa ${i + 1}: kaldırılan alanda siyah olmayan piksel bulundu.',
            sha256: sha256Digest,
            fileSize: fileSize,
          );
        }
      }
      final cleanDigest = FileUtils.sha256OfBytes(
        clean.getBytes(order: img.ChannelOrder.rgb),
      );
      if (!unmatched.remove(cleanDigest)) {
        return _fail(
          path,
          'Sayfa ${i + 1}: dosyadaki görüntü temizlenmiş görüntüyle aynı değil.',
          sha256: sha256Digest,
          fileSize: fileSize,
        );
      }
      totalAreasVerified += areas.length;
    }
    if (unmatched.isNotEmpty) {
      return _fail(
        path,
        'Dosyada sayfalara ait olmayan bir görüntü bulundu.',
        sha256: sha256Digest,
        fileSize: fileSize,
      );
    }

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(path);
      if (doc.pagesCount != expectedPages.length) {
        return _fail(
          path,
          'Sayfa sayısı eşleşmedi. Beklenen: ${expectedPages.length}, Gerçek: ${doc.pagesCount}',
          sha256: sha256Digest,
          fileSize: fileSize,
        );
      }

      for (var i = 0; i < expectedPages.length; i++) {
        final expected = expectedPages[i];
        final pdfPage = await doc.getPage(i + 1);
        try {
          final expectedPts = CoordinateUtils.outputPageSizePts(
            pixelWidth: expected.width,
            pixelHeight: expected.height,
            sourceDpi: expected.sourceDpi,
          );
          if ((pdfPage.width - expectedPts.width).abs() > 1.5 ||
              (pdfPage.height - expectedPts.height).abs() > 1.5) {
            return _fail(
              path,
              'Sayfa ${i + 1} boyutu beklenenle eşleşmiyor.',
              sha256: sha256Digest,
              fileSize: fileSize,
            );
          }

          final cleanFile = cleanImagesMap[expected.id];
          if (cleanFile == null) {
            return _fail(
              path,
              'Sayfa ${i + 1} için temiz görüntü bulunamadı.',
              sha256: sha256Digest,
              fileSize: fileSize,
            );
          }
          final thumbOk = await _pageMatchesCleanImage(pdfPage, cleanFile);
          if (!thumbOk) {
            return _fail(
              path,
              'Sayfa ${i + 1} içeriği veya sırası beklenenle eşleşmiyor.',
              sha256: sha256Digest,
              fileSize: fileSize,
            );
          }

          final areas = redactionsMap[expected.id] ?? const <RedactionArea>[];
          if (areas.isEmpty) continue;

          final rendered = await _render(
            pdfPage,
            expected.width,
            expected.height,
          );
          if (rendered == null) {
            return _fail(
              path,
              'Doğrulama için sayfa ${i + 1} yeniden okunamadı.',
              sha256: sha256Digest,
              fileSize: fileSize,
            );
          }

          final renderInset = max(
            3,
            (max(expected.width, expected.height) * 0.003).ceil(),
          );
          for (final area in areas) {
            if (!_isAreaSolidBlack(rendered, area, inset: renderInset)) {
              PrivacyLogger.logError('RENDERED_AREA_NOT_BLACK');
              return _fail(
                path,
                'Sayfa ${i + 1}: görüntüleyicide kaldırılan alan siyah görünmüyor.',
                sha256: sha256Digest,
                fileSize: fileSize,
              );
            }
          }
        } finally {
          await pdfPage.close();
        }
      }
    } catch (e) {
      PrivacyLogger.logError('VERIFICATION_ENGINE_FAIL', e);
      return _fail(
        path,
        'Dosya bağımsız PDF motoru ile doğrulanamadı.',
        sha256: sha256Digest,
        fileSize: fileSize,
      );
    } finally {
      try {
        await doc?.close();
      } catch (_) {}
    }

    final digestAfter = await FileUtils.computeSha256(generatedPdfFile);
    if (digestAfter != sha256Digest) {
      return _fail(path, 'Dosya doğrulama sırasında değişti.');
    }

    PrivacyLogger.logInfo('OUTPUT_VERIFICATION_SUCCESS');
    return VerificationReport(
      canOpen: true,
      pageCountMatch: true,
      expectedPages: expectedPages.length,
      actualPages: expectedPages.length,
      redactedAreasAreSolidBlack: true,
      totalAreasVerified: totalAreasVerified,
      noTextLayer: true,
      noHiddenAttachments: true,
      sha256Digest: sha256Digest,
      finalPdfPath: path,
      fileSize: fileSize,
    );
  }

  static Future<img.Image?> _render(PdfPage page, int width, int height) async {
    final pageImage = await page.render(
      width: width.toDouble(),
      height: height.toDouble(),
      format: PdfPageImageFormat.png,
      backgroundColor: '#FFFFFF',
    );
    if (pageImage == null) return null;
    final decoded = img.decodePng(pageImage.bytes);
    if (decoded == null) return null;
    if (decoded.width != width || decoded.height != height) {
      return img.copyResize(
        decoded,
        width: width,
        height: height,
        interpolation: img.Interpolation.nearest,
      );
    }
    return decoded;
  }

  static Future<bool> _pageMatchesCleanImage(
    PdfPage page,
    File cleanFile,
  ) async {
    final clean = img.decodePng(await cleanFile.readAsBytes());
    if (clean == null) return false;
    const thumbW = 64;
    final thumbH = max(1, (clean.height * thumbW / clean.width).round());
    final rendered = await _render(page, thumbW, thumbH);
    if (rendered == null) return false;
    final cleanThumb = img.copyResize(
      clean,
      width: thumbW,
      height: thumbH,
      interpolation: img.Interpolation.average,
    );
    return meanAbsDifference(rendered, cleanThumb) <= _orderCheckTolerance;
  }

  static double meanAbsDifference(img.Image a, img.Image b) {
    final w = min(a.width, b.width);
    final h = min(a.height, b.height);
    double total = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pa = a.getPixel(x, y);
        final pb = b.getPixel(x, y);
        total += ((pa.r + pa.g + pa.b) - (pb.r + pb.g + pb.b)).abs() / 3;
      }
    }
    return total / (w * h);
  }

  static bool isAreaSolidBlack(
    img.Image image,
    RedactionArea area, {
    int inset = 0,
  }) => _isAreaSolidBlack(image, area, inset: inset);

  static bool _isAreaSolidBlack(
    img.Image image,
    RedactionArea area, {
    required int inset,
  }) {
    final b = CoordinateUtils.toPixelBounds(
      normalizedRect: area.normalizedRect,
      imageWidth: image.width,
      imageHeight: image.height,
    );
    final maxValue = inset == 0 ? 0 : 8;
    int lo(int a, int bEnd) => min(a + inset, (a + bEnd - 1) ~/ 2);
    int hi(int a, int bEnd) => max(bEnd - 1 - inset, (a + bEnd - 1) ~/ 2);
    final x0 = lo(b.left, b.right), x1 = hi(b.left, b.right);
    final y0 = lo(b.top, b.bottom), y1 = hi(b.top, b.bottom);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final p = image.getPixel(x, y);
        if (p.r > maxValue || p.g > maxValue || p.b > maxValue) return false;
      }
    }
    return true;
  }

  static VerificationReport _fail(
    String path,
    String message, {
    String sha256 = '',
    int fileSize = 0,
  }) {
    PrivacyLogger.logWarning('VERIFICATION_REJECTED');
    return VerificationReport(
      canOpen: false,
      pageCountMatch: false,
      expectedPages: 0,
      actualPages: 0,
      redactedAreasAreSolidBlack: false,
      totalAreasVerified: 0,
      noTextLayer: false,
      noHiddenAttachments: false,
      sha256Digest: sha256,
      finalPdfPath: path,
      fileSize: fileSize,
      failureMessage: message,
    );
  }
}
