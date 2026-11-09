import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';
import 'package:pure_scan/core/constants/app_constants.dart';
import 'package:pure_scan/core/security/privacy_logger.dart';
import 'package:pure_scan/core/theme/app_theme.dart';
import 'package:pure_scan/core/utils/file_utils.dart';
import 'package:pure_scan/shared/models/verification_report.dart';
import 'package:pure_scan/shared/providers/document_session_provider.dart';
import 'package:pure_scan/shared/providers/processing_provider.dart';
import 'package:pure_scan/shared/services/share_guard_service.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _isSharing = false;
  PdfController? _pdfController;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPdfController();
    });
  }

  void _initPdfController() {
    final report = ref.read(processingProvider).verificationReport;
    if (report != null && report.isPassed && mounted) {
      setState(() {
        _pdfController = PdfController(
          document: PdfDocument.openFile(report.finalPdfPath),
        );
      });
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  void _snack(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  Future<void> _handleShare(VerificationReport report) async {
    setState(() => _isSharing = true);
    try {
      final outcome = await ShareGuardService.shareVerifiedPdf(report: report);

      switch (outcome) {
        case ShareOutcome.shared:
          _snack('Paylaşım ekranında bir hedef seçildi.', AppTheme.accentGreen);
        case ShareOutcome.dismissed:
          _snack('Paylaşım iptal edildi.', AppTheme.surfaceDark);
        case ShareOutcome.unknown:
          break;
      }
    } on ShareBlockedException catch (e) {
      PrivacyLogger.logError('SHARE_BLOCKED', e);
      _snack(e.message, AppTheme.accentRed);
    } catch (e) {
      PrivacyLogger.logError('SHARE_FAILED', e);
      _snack('Paylaşım yapılamadı.', AppTheme.accentRed);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _handleSave(VerificationReport report) async {
    setState(() => _isSharing = true);
    try {
      final saved = await ShareGuardService.saveVerifiedPdf(report: report);
      if (saved) {
        _snack(
          'Temiz dosya seçtiğiniz konuma kaydedildi.',
          AppTheme.accentGreen,
        );
      }
    } on ShareBlockedException catch (e) {
      _snack(e.message, AppTheme.accentRed);
    } catch (e) {
      PrivacyLogger.logError('SAVE_FAILED', e);
      _snack('Dosya kaydedilemedi.', AppTheme.accentRed);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _handleNewScan() async {
    _pdfController?.dispose();
    _pdfController = null;
    await ref.read(documentSessionProvider.notifier).cancelSession();
    ref.read(processingProvider.notifier).reset();
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(processingProvider).verificationReport;

    if (report == null || !report.isPassed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hata')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppTheme.accentRed,
              ),
              const SizedBox(height: 16),
              const Text(
                'Dosya kontrol edilemedi, paylaşım yapılmadı',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.accentRed,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Ana Ekrana Dön'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Son Dosya'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'Yeni belge',
          onPressed: _isSharing ? null : _handleNewScan,
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppTheme.accentAmber.withValues(alpha: 0.12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppTheme.accentAmber,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppConstants.postVerificationAdvisory,
                    style: const TextStyle(
                      color: AppTheme.textLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              child: _pdfController != null
                  ? PdfView(
                      controller: _pdfController!,
                      scrollDirection: Axis.vertical,
                      pageSnapping: false,
                      physics: const BouncingScrollPhysics(),
                      backgroundDecoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceDark,
              border: Border(top: BorderSide(color: Color(0xFF334155))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.verified,
                          color: AppTheme.accentGreen,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Teknik kontroller geçti',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppTheme.accentGreen,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      FileUtils.formatBytes(report.fileSize),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                _buildCheckItem(
                  'Dosya açıldı; sayfa sayısı, sırası ve boyutları eşleşti (${report.actualPages} sayfa)',
                ),
                _buildCheckItem(
                  'Seçilen ${report.totalAreasVerified} alan son dosyada düz siyah',
                ),
                _buildCheckItem(
                  'Seçilebilir metin veya gizli metin katmanı yok',
                ),
                _buildCheckItem(
                  'Ek, yorum, form, betik, eski sürüm veya kaynak bilgisi yok',
                ),
                _buildCheckItem(
                  'Paylaşılan dosya = kontrol edilen dosya (SHA-256 ${report.sha256Digest.substring(0, 10)}…)',
                ),

                const SizedBox(height: 16),

                SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSharing
                              ? null
                              : () => _handleSave(report),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Kaydet'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isSharing
                              ? null
                              : () => _handleShare(report),
                          icon: _isSharing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.share_outlined),
                          label: const Text('Paylaş'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check, size: 14, color: AppTheme.accentGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
