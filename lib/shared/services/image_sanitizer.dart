import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../core/security/privacy_logger.dart';

class ImageSanitizer {
  ImageSanitizer._();

  static img.Image flatten(img.Image source) {
    final oriented = img.bakeOrientation(source);
    final rgbSource = oriented.convert(format: img.Format.uint8);

    final out = img.Image(
      width: rgbSource.width,
      height: rgbSource.height,
      numChannels: 3,
    );
    img.fill(out, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(out, rgbSource);
    return out;
  }

  static img.Image decodeAndFlatten(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      PrivacyLogger.logError('IMAGE_DECODE_FAILED');
      throw const ImageImportException(
        'Görüntü okunamadı veya desteklenmiyor.',
      );
    }
    return flatten(decoded);
  }

  static Future<File> writePng(img.Image image, String path) async {
    final file = File(path);
    await file.writeAsBytes(img.encodePng(image), flush: true);
    return file;
  }

  static String? assessQuality(img.Image image) {
    final shortSide = min(image.width, image.height);
    if (shortSide < 700) {
      return 'Çözünürlük düşük. Küçük yazılar okunmayabilir; yeniden taramayı düşünün.';
    }

    final targetWidth = min(600, image.width);
    final small = img.grayscale(img.copyResize(image, width: targetWidth));
    final w = small.width;
    final h = small.height;
    if (w < 3 || h < 3) return null;

    double sum = 0;
    double sumSq = 0;
    var n = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final c = small.getPixel(x, y).r.toDouble();
        final lap =
            small.getPixel(x - 1, y).r +
            small.getPixel(x + 1, y).r +
            small.getPixel(x, y - 1).r +
            small.getPixel(x, y + 1).r -
            4 * c;
        sum += lap;
        sumSq += lap * lap;
        n++;
      }
    }
    final mean = sum / n;
    final variance = sumSq / n - mean * mean;
    if (variance < 40) {
      return 'Sayfa bulanık görünüyor. Yeniden taramanız önerilir.';
    }
    return null;
  }
}

class ImageImportException implements Exception {
  final String message;
  const ImageImportException(this.message);
  @override
  String toString() => message;
}
