import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_scan/core/theme/app_theme.dart';
import 'package:pure_scan/shared/providers/processing_provider.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  final String? customFileName;

  const ProcessingScreen({super.key, this.customFileName});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _executeProcessing();
    });
  }

  Future<void> _executeProcessing() async {
    final report = await ref
        .read(processingProvider.notifier)
        .processDocument(customFileName: widget.customFileName);

    if (!mounted) return;
    if (report != null && report.isPassed) {
      context.pushReplacement('/result');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(processingProvider);

    return PopScope(
      canPop: state.phase == ProcessingPhase.failed,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (state.phase == ProcessingPhase.failed) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline,
                        color: AppTheme.accentRed,
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Dosya kontrol edilemedi, paylaşım yapılmadı',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentRed,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.errorMessage ??
                          'Teknik güvenlik kontrolleri geçilemedi.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () => context.pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surfaceDark,
                      ),
                      child: const Text('Düzenleme Ekranına Dön'),
                    ),
                  ] else ...[
                    const SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        color: AppTheme.accentGreen,
                        strokeWidth: 4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Yeni PDF hazırlanıyor',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 40),

                    _buildStepItem(
                      title: '1. Seçilen pikseller düz siyahla değiştiriliyor',
                      isDone: state.progress >= 0.50,
                      isActive: state.phase == ProcessingPhase.redactingPixels,
                    ),
                    const SizedBox(height: 16),
                    _buildStepItem(
                      title: '2. Temiz görüntülerden yeni PDF oluşturuluyor',
                      isDone: state.progress >= 0.85,
                      isActive: state.phase == ProcessingPhase.buildingPdf,
                    ),
                    const SizedBox(height: 16),
                    _buildStepItem(
                      title: '3. Kaydedilen dosya üzerinde zorunlu kontroller',
                      isDone: state.progress >= 1.0,
                      isActive: state.phase == ProcessingPhase.verifyingOutput,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem({
    required String title,
    required bool isDone,
    required bool isActive,
  }) {
    Color color = AppTheme.textMuted;
    Widget icon = const Icon(
      Icons.circle_outlined,
      size: 18,
      color: AppTheme.textMuted,
    );

    if (isDone) {
      color = AppTheme.accentGreen;
      icon = const Icon(
        Icons.check_circle,
        size: 18,
        color: AppTheme.accentGreen,
      );
    } else if (isActive) {
      color = AppTheme.primaryBlue;
      icon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.primaryBlue,
        ),
      );
    }

    return Row(
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: isDone || isActive
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}
