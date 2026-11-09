import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pure_scan/core/utils/coordinate_utils.dart';
import 'package:pure_scan/shared/models/redaction_area.dart';
import 'package:pure_scan/shared/models/scanned_page.dart';
import 'package:pure_scan/shared/services/clean_pdf_builder_service.dart';
import 'package:pure_scan/shared/services/image_sanitizer.dart';
import 'package:pure_scan/shared/services/output_verifier_service.dart';
import 'package:pure_scan/shared/services/pdf_structure_inspector.dart';
import 'package:pure_scan/shared/services/pixel_redactor_service.dart';

img.Image noisyPage(int w, int h, {int seed = 1}) {
  final rnd = Random(seed);
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (final p in im) {
    p
      ..r = rnd.nextInt(256)
      ..g = rnd.nextInt(256)
      ..b = rnd.nextInt(256);
  }
  return im;
}

RedactionArea area(String pageId, Rect r) => RedactionArea(
  id: 'a',
  pageId: pageId,
  normalizedRect: r,
  createdAt: DateTime(2026),
);

Future<({File pdf, Map<String, File> clean, List<ScannedPage> pages})> buildPdf(
  Directory dir,
  List<img.Image> images,
  Map<int, List<Rect>> rects,
) async {
  final pages = <ScannedPage>[];
  final clean = <String, File>{};
  for (var i = 0; i < images.length; i++) {
    final id = 'p$i';
    final areas = (rects[i] ?? const []).map((r) => area(id, r)).toList();
    final redacted = PixelRedactorService.redactImage(images[i], areas);
    final f = await ImageSanitizer.writePng(
      redacted,
      '${dir.path}/clean_$i.png',
    );
    clean[id] = f;
    pages.add(
      ScannedPage(
        id: id,
        originalImagePath: f.path,
        currentImagePath: f.path,
        width: redacted.width,
        height: redacted.height,
        pageIndex: i,
        sourceDpi: i.isEven ? 200 : null,
      ),
    );
  }
  final pdf = await CleanPdfBuilderService.buildCleanPdf(
    pages: pages,
    cleanImagesMap: clean,
    outputPartPath: '${dir.path}/out.pdf.part',
  );
  return (pdf: pdf, clean: clean, pages: pages);
}

List<List<int>> extractRawImages(List<int> pdfBytes) {
  final s = latin1.decode(pdfBytes);
  final out = <List<int>>[];
  final re = RegExp(r'/Subtype\s*/Image[^]*?/Length\s+(\d+)[^]*?stream\r?\n');
  for (final m in re.allMatches(s)) {
    final len = int.parse(m.group(1)!);
    out.add(zlib.decode(pdfBytes.sublist(m.end, m.end + len)));
  }
  return out;
}

void main() {
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('purescan_test_'),
  );
  tearDown(() async => dir.delete(recursive: true));

  test(
    'Gerçek kaldırma: seçilen alan PDF içindeki görüntü verisinde de siyah',
    () async {
      const w = 400, h = 300;
      final page = img.Image(width: w, height: h, numChannels: 3);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));

      img.fillRect(
        page,
        x1: 100,
        y1: 100,
        x2: 199,
        y2: 149,
        color: img.ColorRgb8(255, 0, 0),
      );
      const secret = Rect.fromLTRB(100 / w, 100 / h, 200 / w, 150 / h);

      final r = await buildPdf(
        dir,
        [page],
        {
          0: [secret],
        },
      );
      final bytes = await r.pdf.readAsBytes();

      final images = extractRawImages(bytes);
      expect(images, hasLength(1));
      final raw = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: Uint8List.fromList(images.first).buffer,
        numChannels: 3,
      );

      for (final p in raw) {
        expect(p.r > 200 && p.g < 50 && p.b < 50, isFalse);
      }
      expect(
        OutputVerifierService.isAreaSolidBlack(raw, area('p0', secret)),
        isTrue,
      );

      final outside = raw.getPixel(20, 20);
      expect([outside.r, outside.g, outside.b], [255, 255, 255]);
    },
  );

  test(
    'Yapı incelemesi: temiz çıktıda yanlış alarm yok (gürültülü görüntülerle)',
    () async {
      final r = await buildPdf(
        dir,
        [
          noisyPage(600, 800, seed: 1),
          noisyPage(500, 700, seed: 2),
          noisyPage(640, 480, seed: 3),
        ],
        {
          1: [const Rect.fromLTRB(0.1, 0.1, 0.5, 0.3)],
        },
      );
      final result = PdfStructureInspector.inspect(await r.pdf.readAsBytes());
      expect(result.problems, isEmpty);
      expect(result.pageObjectCount, 3);
      expect(result.imageObjectCount, 3);
    },
  );

  test('Çıktıda meta veri, metin, alfa maskesi yok; tek sürüm', () async {
    final rgba = img.Image(width: 50, height: 50, numChannels: 4);
    img.fill(rgba, color: img.ColorRgba8(0, 0, 255, 0));
    final r = await buildPdf(dir, [rgba], {});
    final s = latin1.decode(await r.pdf.readAsBytes());
    expect(s.contains('/SMask'), isFalse);
    expect(s.contains('/Author'), isFalse);
    expect(s.contains('/Title'), isFalse);
    expect('%%EOF'.allMatches(s).length, 1);

    final raw = extractRawImages(await r.pdf.readAsBytes()).first;
    expect(raw.sublist(0, 3), [255, 255, 255]);
  });

  test('Yapı incelemesi metin, yorum, ek ve eski sürümü yakalar', () async {
    final doc = pw.Document(title: 'DENEME-GIZLI-8472', author: 'Gizli Yazar');
    doc.addPage(pw.Page(build: (_) => pw.Text('DENEME-GIZLI-8472')));
    final bytes = await doc.save();
    final result = PdfStructureInspector.inspect(bytes);
    expect(result.isClean, isFalse);
    expect(result.problems.join(' '), contains('yazı tipi'));

    final r = await buildPdf(dir, [noisyPage(100, 100)], {});
    final original = await r.pdf.readAsBytes();
    final appended = [
      ...original,
      ...latin1.encode(
        '\n1 0 obj\n<< /Annots [] >>\nendobj\ntrailer\n<< /Prev 10 >>\n%%EOF\n',
      ),
    ];
    final res2 = PdfStructureInspector.inspect(Uint8List.fromList(appended));
    expect(res2.isClean, isFalse);
  });

  test('Kaynak özellik tespiti: form, ek, yorum', () {
    final fake = latin1.encode(
      '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /AcroForm 2 0 R /Names << /EmbeddedFiles 3 0 R >> >>\nendobj\n'
      '2 0 obj\n<< /Annots [] >>\nendobj\ntrailer\n<< >>\n%%EOF',
    );
    final f = PdfStructureInspector.detectSourceFeatures(
      Uint8List.fromList(fake),
    );
    expect(f.hasForms, isTrue);
    expect(f.hasAttachments, isTrue);
    expect(f.hasAnnotations, isTrue);
    expect(f.hasSignature, isFalse);
  });

  test('Görüntü temizleme: EXIF ve alfa atılır, yön uygulanır', () {
    final src = img.Image(width: 20, height: 10, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(10, 20, 30, 255));
    src.exif.imageIfd['GPSLatitude'] = img.IfdValueAscii('41.0');
    src.exif.imageIfd.orientation = 6;
    final out = ImageSanitizer.flatten(src);
    expect(out.numChannels, 3);
    expect(out.exif.isEmpty, isTrue);
    expect(out.width, 10);
    expect(out.height, 20);
    final png = img.encodePng(out);
    expect(latin1.decode(png).contains('eXIf'), isFalse);
  });

  test('Döndürme sonrası seçim aynı içeriğin üzerinde kalır', () {
    const w = 300, h = 200;
    final im = img.Image(width: w, height: h, numChannels: 3);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      im,
      x1: 30,
      y1: 40,
      x2: 89,
      y2: 79,
      color: img.ColorRgb8(255, 0, 0),
    );
    const sel = Rect.fromLTRB(30 / w, 40 / h, 90 / w, 80 / h);

    var rotated = im;
    var rect = sel;
    for (var i = 0; i < 4; i++) {
      rotated = img.copyRotate(rotated, angle: 90);
      rect = CoordinateUtils.rotateNormalized90Clockwise(rect);
      final redacted = PixelRedactorService.redactImage(rotated, [
        area('p', rect),
      ]);
      for (final p in redacted) {
        expect(
          p.r > 200 && p.g < 50,
          isFalse,
          reason: 'döndürme $i sonrası kırmızı kaldı',
        );
      }
    }
    expect(rect.left, closeTo(sel.left, 1e-9));
    expect(rect.bottom, closeTo(sel.bottom, 1e-9));
  });

  test('Kırpma sonrası seçim doğru yere taşınır, dışarıda kalan atılır', () {
    const crop = Rect.fromLTRB(0.2, 0.2, 0.8, 0.8);
    final moved = CoordinateUtils.cropNormalized(
      const Rect.fromLTRB(0.3, 0.3, 0.5, 0.5),
      crop,
    )!;
    expect(moved.left, closeTo(1 / 6, 1e-9));
    expect(moved.right, closeTo(0.5, 1e-9));
    expect(
      CoordinateUtils.cropNormalized(const Rect.fromLTRB(0, 0, 0.1, 0.1), crop),
      isNull,
    );
  });

  test(
    'Çıktı sayfa boyutu: PDF kaynağı orijinal boyuta, fotoğraf A4 uzun kenarına',
    () {
      final a4 = CoordinateUtils.outputPageSizePts(
        pixelWidth: 1654,
        pixelHeight: 2339,
        sourceDpi: 200,
      );
      expect(a4.width, 595);
      expect(a4.height, 842);
      final photo = CoordinateUtils.outputPageSizePts(
        pixelWidth: 3000,
        pixelHeight: 4000,
      );
      expect(photo.height, closeTo(842, 0.01));
    },
  );

  test(
    'PdfPageFormat ile üretilen PDF de incelemeden geçer (pdf paketi sürüm uyumu)',
    () async {
      final doc = pw.Document(version: PdfVersion.pdf_1_4);
      doc.addPage(pw.Page(build: (_) => pw.SizedBox()));
      final res = PdfStructureInspector.inspect(await doc.save());
      expect(res.problems, isEmpty);
    },
  );

  test(
    'Gömülü görüntü, temizlenmiş görüntüyle bayt bayt eşleşir; silinmemiş görüntü yakalanır',
    () async {
      final page = noisyPage(3000, 4000, seed: 7);
      const sel = Rect.fromLTRB(0.62, 0.81, 0.97, 0.86);
      final r = await buildPdf(
        dir,
        [page],
        {
          0: [sel],
        },
      );
      final pdfBytes = await r.pdf.readAsBytes();

      final clean = img.decodePng(await r.clean['p0']!.readAsBytes())!;
      expect(
        OutputVerifierService.isAreaSolidBlack(clean, area('p0', sel)),
        isTrue,
      );
      final cleanDigest = sha256
          .convert(clean.getBytes(order: img.ChannelOrder.rgb))
          .toString();
      final embedded = PdfStructureInspector.embeddedImageDigests(pdfBytes);
      expect(embedded.map((e) => e.digest), [cleanDigest]);

      final original = ImageSanitizer.flatten(page);
      final originalDigest = sha256
          .convert(original.getBytes(order: img.ChannelOrder.rgb))
          .toString();
      expect(embedded.map((e) => e.digest), isNot(contains(originalDigest)));
      expect(
        OutputVerifierService.isAreaSolidBlack(original, area('p0', sel)),
        isFalse,
      );
    },
  );
}
