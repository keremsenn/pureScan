import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pure_scan/core/utils/coordinate_utils.dart';
import 'package:pure_scan/core/utils/file_utils.dart';

void main() {
  group('CoordinateUtils & Pixel Security Margin Tests (Brief Section 4)', () {
    test(
      'Normalized to pixel bounds applies outward rounding and security margins',
      () {
        const imgWidth = 1000;
        const imgHeight = 2000;
        const normalizedRect = Rect.fromLTWH(0.25, 0.40, 0.10, 0.05);

        final bounds = CoordinateUtils.toPixelBounds(
          normalizedRect: normalizedRect,
          imageWidth: imgWidth,
          imageHeight: imgHeight,
          securityMargin: 6,
        );

        expect(bounds.left, equals(244));

        expect(bounds.top, equals(794));

        expect(bounds.right, equals(356));

        expect(bounds.bottom, equals(906));
      },
    );

    test('Bounds are strictly clamped within image dimensions near edges', () {
      const imgWidth = 500;
      const imgHeight = 500;
      const nearEdgeRect = Rect.fromLTWH(0.001, 0.001, 0.998, 0.998);

      final bounds = CoordinateUtils.toPixelBounds(
        normalizedRect: nearEdgeRect,
        imageWidth: imgWidth,
        imageHeight: imgHeight,
        securityMargin: 10,
      );

      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(imgWidth));
      expect(bounds.bottom, lessThanOrEqualTo(imgHeight));
    });
  });

  group('True Physical Pixel Redaction Test (Brief Section 4 & 8)', () {
    test('Overwrites underlying pixels with solid black (0x000000)', () {
      final testImg = img.Image(width: 200, height: 200);
      img.fill(testImg, color: img.ColorRgb8(255, 255, 255));

      final beforePixel = testImg.getPixel(100, 100);
      expect(beforePixel.r, equals(255));
      expect(beforePixel.g, equals(255));
      expect(beforePixel.b, equals(255));

      const normalizedRect = Rect.fromLTWH(0.40, 0.40, 0.20, 0.20);
      final bounds = CoordinateUtils.toPixelBounds(
        normalizedRect: normalizedRect,
        imageWidth: testImg.width,
        imageHeight: testImg.height,
        securityMargin: 4,
      );

      img.fillRect(
        testImg,
        x1: bounds.left,
        y1: bounds.top,
        x2: bounds.right,
        y2: bounds.bottom,
        color: img.ColorRgb8(0, 0, 0),
      );

      for (int y = bounds.top; y < bounds.bottom; y += 4) {
        for (int x = bounds.left; x < bounds.right; x += 4) {
          final pixel = testImg.getPixel(x, y);
          expect(pixel.r, equals(0));
          expect(pixel.g, equals(0));
          expect(pixel.b, equals(0));
        }
      }

      final outsidePixel = testImg.getPixel(10, 10);
      expect(outsidePixel.r, equals(255));
      expect(outsidePixel.g, equals(255));
      expect(outsidePixel.b, equals(255));
    });
  });

  group('FileUtils Neutral Naming & Security Tests (Brief Section 3)', () {
    test('Neutral default filename is preserved and sanitized', () {
      expect(
        FileUtils.sanitizePdfFileName(null),
        equals('belge_temizlenmis.pdf'),
      );
      expect(
        FileUtils.sanitizePdfFileName(''),
        equals('belge_temizlenmis.pdf'),
      );
      expect(
        FileUtils.sanitizePdfFileName('gizli_rapor'),
        equals('gizli_rapor.pdf'),
      );
    });

    test('Sanitizes unsafe characters in output filenames', () {
      final sanitized = FileUtils.sanitizePdfFileName('sozlesme/hesap:123.pdf');
      expect(sanitized, equals('sozlesme_hesap_123.pdf'));
    });
  });
}
