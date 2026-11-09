import 'package:flutter/foundation.dart';

class PrivacyLogger {
  PrivacyLogger._();

  static void logInfo(String eventCode, [String? safeMessage]) {
    if (kDebugMode) {
      debugPrint(
        '[PureScan-SECURE-LOG] INFO: [$eventCode] ${safeMessage ?? ''}',
      );
    }
  }

  static void logWarning(String warningCode, [String? safeMessage]) {
    if (kDebugMode) {
      debugPrint(
        '[PureScan-SECURE-LOG] WARN: [$warningCode] ${safeMessage ?? ''}',
      );
    }
  }

  static void logError(String errorCode, [Object? error]) {
    if (kDebugMode) {
      debugPrint(
        '[PureScan-SECURE-LOG] ERROR: [$errorCode] (Class: ${error?.runtimeType})',
      );
    }
  }
}
