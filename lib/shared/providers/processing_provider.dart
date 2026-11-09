import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/security/privacy_logger.dart';
import '../../core/security/temp_file_manager.dart';
import '../models/verification_report.dart';
import '../services/clean_pdf_builder_service.dart';
import '../services/output_verifier_service.dart';
import '../services/pixel_redactor_service.dart';
import 'document_session_provider.dart';

enum ProcessingPhase {
  idle,
  redactingPixels,
  buildingPdf,
  verifyingOutput,
  completed,
  failed,
}

class ProcessingState {
  final ProcessingPhase phase;
  final double progress;
  final String statusMessage;
  final VerificationReport? verificationReport;
  final String? errorMessage;

  const ProcessingState({
    this.phase = ProcessingPhase.idle,
    this.progress = 0.0,
    this.statusMessage = '',
    this.verificationReport,
    this.errorMessage,
  });

  bool get isProcessing =>
      phase == ProcessingPhase.redactingPixels ||
      phase == ProcessingPhase.buildingPdf ||
      phase == ProcessingPhase.verifyingOutput;

  bool get isSuccess =>
      phase == ProcessingPhase.completed &&
      verificationReport?.isPassed == true;
}

class ProcessingNotifier extends Notifier<ProcessingState> {
  @override
  ProcessingState build() => const ProcessingState();

  Future<VerificationReport?> processDocument({String? customFileName}) async {
    state = const ProcessingState();
    final session = ref.read(documentSessionProvider);
    final sessionDir = session.sessionDir;
    final pages = List.of(session.pages);
    final redactions = Map.of(session.redactionsMap);

    if (sessionDir == null || pages.isEmpty) {
      state = const ProcessingState(
        phase: ProcessingPhase.failed,
        errorMessage: 'İşlenecek sayfa bulunamadı.',
      );
      return null;
    }

    File? partFile;
    try {
      state = const ProcessingState(
        phase: ProcessingPhase.redactingPixels,
        progress: 0.25,
        statusMessage:
            'Seçilen alanlardaki pikseller düz siyahla değiştiriliyor...',
      );
      final cleanImagesMap =
          await PixelRedactorService.applyRedactionsToAllPages(
            pages: pages,
            redactionsMap: redactions,
            sessionDir: sessionDir,
          );

      state = const ProcessingState(
        phase: ProcessingPhase.buildingPdf,
        progress: 0.55,
        statusMessage: 'Temiz görüntülerden yeni PDF oluşturuluyor...',
      );
      partFile = await CleanPdfBuilderService.buildCleanPdf(
        pages: pages,
        cleanImagesMap: cleanImagesMap,
        outputPartPath: TempFileManager.getPartialPdfPath(sessionDir),
      );

      state = const ProcessingState(
        phase: ProcessingPhase.verifyingOutput,
        progress: 0.85,
        statusMessage:
            'Kaydedilen dosya üzerinde zorunlu kontroller yapılıyor...',
      );
      final partReport = await OutputVerifierService.verifyOutputPdf(
        generatedPdfFile: partFile,
        expectedPages: pages,
        redactionsMap: redactions,
        cleanImagesMap: cleanImagesMap,
      );

      for (final f in cleanImagesMap.values) {
        try {
          await f.delete();
        } catch (_) {}
      }

      if (!partReport.isPassed) {
        await _deleteQuietly(partFile);
        state = ProcessingState(
          phase: ProcessingPhase.failed,
          progress: 1.0,
          errorMessage:
              partReport.failureMessage ??
              'Dosya kontrol edilemedi, paylaşım yapılmadı.',
        );
        PrivacyLogger.logError('PIPELINE_FAILED_AT_VERIFICATION');
        return partReport;
      }

      final finalPath = await TempFileManager.getVerifiedPdfPath(
        sessionDir,
        customFileName ?? 'belge_temizlenmis.pdf',
      );
      final finalFile = File(finalPath);
      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(finalPath);

      final report = partReport.withPath(finalPath);
      state = ProcessingState(
        phase: ProcessingPhase.completed,
        progress: 1.0,
        statusMessage: 'Kontroller tamamlandı.',
        verificationReport: report,
      );
      return report;
    } catch (e) {
      PrivacyLogger.logError('PIPELINE_EXCEPTION', e);
      if (partFile != null) await _deleteQuietly(partFile);
      state = ProcessingState(
        phase: ProcessingPhase.failed,
        progress: 1.0,
        errorMessage: _userMessage(e),
      );
      return null;
    }
  }

  static String _userMessage(Object e) {
    if (e is FileSystemException) {
      return 'Dosya yazılamadı. Cihazda yeterli boş alan olduğundan emin olun.';
    }
    final text = e.toString().replaceFirst('Exception: ', '');
    return text.length > 200
        ? 'İşlem sırasında beklenmeyen bir hata oluştu.'
        : text;
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void reset() {
    state = const ProcessingState();
  }
}

final processingProvider =
    NotifierProvider<ProcessingNotifier, ProcessingState>(
      ProcessingNotifier.new,
    );
