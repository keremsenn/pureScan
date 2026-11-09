import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class PdfStructureInspector {
  PdfStructureInspector._();

  static final RegExp _objHeader = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
  static final RegExp _directLength = RegExp(r'/Length\s+(\d+)(?!\s+\d+\s+R)');

  static const Map<String, String> _forbiddenNames = {
    '/Font': 'yazı tipi',
    '/FontDescriptor': 'yazı tipi',
    '/Annots': 'yorum / açıklama',
    '/Annot': 'yorum / açıklama',
    '/AcroForm': 'form alanı',
    '/XFA': 'form alanı',
    '/EmbeddedFiles': 'ekli dosya',
    '/EmbeddedFile': 'ekli dosya',
    '/FileAttachment': 'ekli dosya',
    '/JavaScript': 'betik',
    '/JS': 'betik',
    '/OpenAction': 'otomatik eylem',
    '/AA': 'otomatik eylem',
    '/URI': 'bağlantı eylemi',
    '/Launch': 'bağlantı eylemi',
    '/GoToR': 'bağlantı eylemi',
    '/OCProperties': 'gizli katman',
    '/OCG': 'gizli katman',
    '/Metadata': 'XMP meta verisi',
    '/Outlines': 'yer imi',
    '/Names': 'ad ağacı',
    '/PieceInfo': 'uygulama verisi',
    '/Thumb': 'küçük önizleme',
    '/SMask': 'saydam katman',
    '/Mask': 'saydam katman',
    '/ObjStm': 'incelenemeyen nesne akışı',
    '/XRefStm': 'incelenemeyen xref akışı',
    '/Encrypt': 'şifreleme',
    '/Sig': 'imza',
    '/Author': 'yazar bilgisi',
    '/Title': 'belge başlığı',
    '/Subject': 'belge konusu',
    '/Keywords': 'anahtar kelime',
    '/Creator': 'oluşturan uygulama',
  };

  static final RegExp _textOperator = RegExp(
    r'(^|[\s\]\)>])(BT|ET|Tj|TJ|Tf|Td|TD|Tm|T\*)(?=[\s\[\(<]|$)',
  );

  static PdfInspectionResult inspect(Uint8List bytes) {
    final s = latin1.decode(bytes);
    final problems = <String>[];

    if (!s.startsWith('%PDF-')) {
      return PdfInspectionResult(
        problems: ['Dosya geçerli bir PDF başlığı içermiyor.'],
      );
    }

    final objects = _parseObjects(bytes, s, problems);
    var pageCount = 0;
    var imageCount = 0;
    var textStreams = 0;

    for (final o in objects) {
      final dict = o.dict;
      for (final entry in _forbiddenNames.entries) {
        if (_hasName(dict, entry.key)) {
          problems.add('Yasaklı öğe bulundu: ${entry.value} (${entry.key}).');
        }
      }
      if (_hasName(dict, '/Type') &&
          RegExp(r'/Type\s*/Page(?![A-Za-z])').hasMatch(dict)) {
        pageCount++;
      }
      if (RegExp(r'/Type\s*/XRef(?![A-Za-z])').hasMatch(dict)) {
        problems.add('Xref akışı incelenemiyor.');
      }

      final isImage = RegExp(r'/Subtype\s*/Image(?![A-Za-z])').hasMatch(dict);
      if (isImage) {
        imageCount++;
        continue;
      }

      if (o.stream != null) {
        final content = _decodeStream(dict, o.stream!);
        if (content == null) {
          problems.add('Çözülemeyen bir veri akışı bulundu.');
        } else if (_textOperator.hasMatch(content)) {
          textStreams++;
        }
      }
    }

    if (textStreams > 0) {
      problems.add('Sayfa içeriğinde metin operatörü bulundu.');
    }

    final eofCount = '%%EOF'.allMatches(s).length;
    if (eofCount != 1) {
      problems.add('Dosyada birden fazla sürüm (artımlı güncelleme) var.');
    }
    final trailerIdx = s.lastIndexOf('trailer');
    if (trailerIdx == -1) {
      problems.add('PDF trailer bölümü bulunamadı.');
    } else {
      final trailer = s.substring(trailerIdx);
      if (_hasName(trailer, '/Prev')) {
        problems.add('Dosyada önceki sürüme işaret eden kayıt var.');
      }
      if (_hasName(trailer, '/Encrypt')) {
        problems.add('Çıktı şifreli olmamalı.');
      }
    }

    return PdfInspectionResult(
      problems: problems.toSet().toList(),
      pageObjectCount: pageCount,
      imageObjectCount: imageCount,
      objectCount: objects.length,
    );
  }

  static SourcePdfFeatures detectSourceFeatures(Uint8List bytes) {
    final s = latin1.decode(bytes);
    final objects = _parseObjects(bytes, s, <String>[]);
    final dicts = objects.map((o) => o.dict).join('\n');
    return SourcePdfFeatures(
      hasForms: _hasName(dicts, '/AcroForm') || _hasName(dicts, '/Widget'),
      hasSignature: _hasName(dicts, '/Sig') || _hasName(dicts, '/ByteRange'),
      hasAnnotations: _hasName(dicts, '/Annots'),
      hasAttachments:
          _hasName(dicts, '/EmbeddedFiles') ||
          _hasName(dicts, '/FileAttachment'),
      hasScripts: _hasName(dicts, '/JavaScript') || _hasName(dicts, '/JS'),
      hasLayers: _hasName(dicts, '/OCProperties'),
      usesObjectStreams: _hasName(dicts, '/ObjStm'),
    );
  }

  static List<EmbeddedImageInfo> embeddedImageDigests(Uint8List bytes) {
    final s = latin1.decode(bytes);
    final result = <EmbeddedImageInfo>[];
    for (final o in _parseObjects(bytes, s, <String>[])) {
      final dict = o.dict;
      if (!RegExp(r'/Subtype\s*/Image(?![A-Za-z])').hasMatch(dict) ||
          o.stream == null) {
        continue;
      }
      final w = int.tryParse(
        RegExp(r'/Width\s+(\d+)').firstMatch(dict)?.group(1) ?? '',
      );
      final h = int.tryParse(
        RegExp(r'/Height\s+(\d+)').firstMatch(dict)?.group(1) ?? '',
      );
      final isRgb8 =
          RegExp(r'/ColorSpace\s*/DeviceRGB').hasMatch(dict) &&
          RegExp(r'/BitsPerComponent\s+8(?!\d)').hasMatch(dict);
      String? digest;
      if (w != null && h != null && isRgb8) {
        try {
          final raw = _hasName(dict, '/FlateDecode')
              ? zlib.decode(o.stream!)
              : o.stream!;
          if (raw.length == w * h * 3) digest = sha256.convert(raw).toString();
        } catch (_) {}
      }
      result.add(
        EmbeddedImageInfo(width: w ?? 0, height: h ?? 0, digest: digest),
      );
    }
    return result;
  }

  static bool _hasName(String text, String name) {
    return RegExp('${RegExp.escape(name)}(?![A-Za-z0-9#_.\\-])').hasMatch(text);
  }

  static List<_RawObject> _parseObjects(
    Uint8List bytes,
    String s,
    List<String> problems,
  ) {
    final result = <_RawObject>[];
    var pos = 0;
    while (true) {
      final m = _firstMatchFrom(_objHeader, s, pos);
      if (m == null) break;
      final bodyStart = m.end;
      final endObj = s.indexOf('endobj', bodyStart);
      final streamKw = _findStreamKeyword(s, bodyStart);

      if (streamKw != -1 && (endObj == -1 || streamKw < endObj)) {
        final dict = s.substring(bodyStart, streamKw);
        var dataStart = streamKw + 'stream'.length;
        if (dataStart < s.length && s.codeUnitAt(dataStart) == 0x0D) {
          dataStart++;
        }
        if (dataStart < s.length && s.codeUnitAt(dataStart) == 0x0A) {
          dataStart++;
        }

        int dataEnd;
        final lenMatch = _directLength.firstMatch(dict);
        if (lenMatch != null) {
          dataEnd = dataStart + int.parse(lenMatch.group(1)!);
        } else {
          dataEnd = s.indexOf('endstream', dataStart);
        }
        if (dataEnd < dataStart || dataEnd > bytes.length) {
          problems.add('Bozuk veri akışı uzunluğu.');
          break;
        }
        result.add(
          _RawObject(dict, Uint8List.sublistView(bytes, dataStart, dataEnd)),
        );
        final next = s.indexOf('endobj', dataEnd);
        if (next == -1) {
          problems.add('Kapanmamış PDF nesnesi.');
          break;
        }
        pos = next + 'endobj'.length;
      } else {
        if (endObj == -1) {
          problems.add('Kapanmamış PDF nesnesi.');
          break;
        }
        result.add(_RawObject(s.substring(bodyStart, endObj), null));
        pos = endObj + 'endobj'.length;
      }
    }
    return result;
  }

  static RegExpMatch? _firstMatchFrom(RegExp re, String s, int start) {
    final it = re.allMatches(s, start).iterator;
    return it.moveNext() ? it.current : null;
  }

  static int _findStreamKeyword(String s, int from) {
    var idx = s.indexOf('stream', from);
    while (idx != -1) {
      final isEndStream = idx >= 3 && s.substring(idx - 3, idx) == 'end';
      if (!isEndStream) return idx;
      idx = s.indexOf('stream', idx + 6);
    }
    return -1;
  }

  static String? _decodeStream(String dict, Uint8List data) {
    try {
      if (_hasName(dict, '/Filter')) {
        if (!_hasName(dict, '/FlateDecode')) return null;
        return latin1.decode(zlib.decode(data));
      }
      return latin1.decode(data);
    } catch (_) {
      return null;
    }
  }
}

class EmbeddedImageInfo {
  final int width;
  final int height;
  final String? digest;
  const EmbeddedImageInfo({
    required this.width,
    required this.height,
    this.digest,
  });
}

class _RawObject {
  final String dict;
  final Uint8List? stream;
  _RawObject(this.dict, this.stream);
}

class PdfInspectionResult {
  final List<String> problems;
  final int pageObjectCount;
  final int imageObjectCount;
  final int objectCount;

  const PdfInspectionResult({
    required this.problems,
    this.pageObjectCount = 0,
    this.imageObjectCount = 0,
    this.objectCount = 0,
  });

  bool get isClean => problems.isEmpty;
}

class SourcePdfFeatures {
  final bool hasForms;
  final bool hasSignature;
  final bool hasAnnotations;
  final bool hasAttachments;
  final bool hasScripts;
  final bool hasLayers;
  final bool usesObjectStreams;

  const SourcePdfFeatures({
    this.hasForms = false,
    this.hasSignature = false,
    this.hasAnnotations = false,
    this.hasAttachments = false,
    this.hasScripts = false,
    this.hasLayers = false,
    this.usesObjectStreams = false,
  });

  List<String> get droppedFeatureLabels => [
    if (hasForms)
      'Doldurulabilir form alanları (değerleri görüntüde görünmeyebilir, önizlemeyi kontrol edin)',
    if (hasSignature) 'Dijital imza (yeni kopya imza doğrulamasını taşımaz)',
    if (hasAnnotations) 'Yorumlar ve açıklamalar',
    if (hasAttachments) 'Ekli dosyalar',
    if (hasScripts) 'Betikler (çalıştırılmadı)',
    if (hasLayers) 'Katmanlar (gizli katmanlar çıktıya taşınmaz)',
  ];
}
