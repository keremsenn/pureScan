import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../constants/app_constants.dart';

class FileUtils {
  FileUtils._();

  static Future<String> computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static String sha256OfBytes(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  static String sanitizePdfFileName(String? rawName) {
    if (rawName == null || rawName.trim().isEmpty) {
      return AppConstants.defaultOutputFileName;
    }
    var cleaned = rawName.trim();
    const tr = {
      'ı': 'i',
      'İ': 'I',
      'ş': 's',
      'Ş': 'S',
      'ğ': 'g',
      'Ğ': 'G',
      'ü': 'u',
      'Ü': 'U',
      'ö': 'o',
      'Ö': 'O',
      'ç': 'c',
      'Ç': 'C',
    };
    tr.forEach((k, v) => cleaned = cleaned.replaceAll(k, v));
    cleaned = cleaned.replaceAll(RegExp(r'[^\w\.\-]'), '_');

    cleaned = cleaned.replaceAll(RegExp(r'^\.+'), '');
    if (cleaned.toLowerCase().endsWith('.pdf')) {
      cleaned = cleaned.substring(0, cleaned.length - 4);
    }
    if (cleaned.isEmpty) return AppConstants.defaultOutputFileName;
    if (cleaned.length > 80) cleaned = cleaned.substring(0, 80);
    return '$cleaned.pdf';
  }
}
