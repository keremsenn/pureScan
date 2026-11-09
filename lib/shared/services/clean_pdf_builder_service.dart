import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/security/privacy_logger.dart';
import '../../core/utils/coordinate_utils.dart';
import '../models/scanned_page.dart';

class CleanPdfBuilderService {
  CleanPdfBuilderService._();

  static Future<File> buildCleanPdf({
    required List<ScannedPage> pages,
    required Map<String, File> cleanImagesMap,
    required String outputPartPath,
  }) async {
    PrivacyLogger.logInfo('PDF_BUILD_CLEAN_START');

    final pdfDoc = pw.Document(version: PdfVersion.pdf_1_4, compress: true);

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final cleanFile = cleanImagesMap[page.id];
      if (cleanFile == null || !await cleanFile.exists()) {
        PrivacyLogger.logError('CLEAN_IMAGE_MISSING');
        throw Exception('Temiz sayfa görüntüsü bulunamadı: Sayfa ${i + 1}');
      }

      final decoded = img.decodePng(await cleanFile.readAsBytes());
      if (decoded == null || decoded.numChannels != 3) {
        throw Exception('Temiz sayfa görüntüsü geçersiz: Sayfa ${i + 1}');
      }
      if (decoded.width != page.width || decoded.height != page.height) {
        throw Exception('Sayfa ${i + 1} boyutu beklenenle eşleşmiyor.');
      }

      final rgb = decoded.getBytes(order: img.ChannelOrder.rgb);
      final pdfImage = PdfImage(
        pdfDoc.document,
        image: rgb,
        width: decoded.width,
        height: decoded.height,
        alpha: false,
      );

      final sizePts = CoordinateUtils.outputPageSizePts(
        pixelWidth: page.width,
        pixelHeight: page.height,
        sourceDpi: page.sourceDpi,
      );

      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            sizePts.width,
            sizePts.height,
            marginAll: 0,
          ),
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(pw.ImageProxy(pdfImage), fit: pw.BoxFit.fill),
          ),
        ),
      );
    }

    final outputFile = File(outputPartPath);
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    await outputFile.writeAsBytes(await pdfDoc.save(), flush: true);

    PrivacyLogger.logInfo('PDF_BUILD_CLEAN_COMPLETE');
    return outputFile;
  }
}
