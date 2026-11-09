import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_scan/core/constants/app_constants.dart';
import 'package:pure_scan/core/theme/app_theme.dart';
import 'package:pure_scan/core/utils/file_utils.dart';
import 'package:pure_scan/shared/providers/document_session_provider.dart';

class ReviewAndWarningScreen extends ConsumerStatefulWidget {
  const ReviewAndWarningScreen({super.key});

  @override
  ConsumerState<ReviewAndWarningScreen> createState() =>
      _ReviewAndWarningScreenState();
}

class _ReviewAndWarningScreenState
    extends ConsumerState<ReviewAndWarningScreen> {
  late final TextEditingController _fileNameController;
  bool _understandTradeOffs = false;

  @override
  void initState() {
    super.initState();

    _fileNameController = TextEditingController(
      text: AppConstants.defaultOutputFileName.replaceAll(
        RegExp(r'\.pdf$'),
        '',
      ),
    );
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  void _startProcessing() {
    final sanitizedName = FileUtils.sanitizePdfFileName(
      _fileNameController.text,
    );
    context.pushReplacement('/processing', extra: sanitizedName);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(documentSessionProvider);
    final pages = session.pages;
    final totalRedactions = session.totalRedactionsCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Son Kontrol ve Onay')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accentRed, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AppTheme.accentRed,
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'DİKKAT: KALICI BİLGİ KALDIRMA',
                        style: TextStyle(
                          color: AppTheme.accentRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    AppConstants.permanentRedactionWarning,
                    style: TextStyle(
                      color: AppTheme.textLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hatırlatma: Aynı bilgi belgenin başka sayfalarında da bulunabilir. Uygulama yalnızca sizin seçtiğiniz alanları kaldırır.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Belge ve Kaldırma Özeti',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.textLight,
                      ),
                    ),
                    const Divider(color: Color(0xFF334155), height: 24),
                    _buildSummaryRow('Toplam Sayfa:', '${pages.length} Sayfa'),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      'Kaldırılacak Alan Sayısı:',
                      '$totalRedactions Alan',
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      'Kaynak Dosya Durumu:',
                      'Değiştirilmeyecek (Dokunulmaz)',
                    ),
                    const SizedBox(height: 12),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int i = 0; i < pages.length; i++)
                          Chip(
                            backgroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFF334155)),
                            label: Text(
                              'Sayfa ${i + 1}: ${(session.redactionsMap[pages[i].id] ?? []).length} alan',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textLight,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (session.sourceFeatures?.droppedFeatureLabels.isNotEmpty ==
                true) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kaynak belgede bulunan ve yeni dosyaya taşınmayacak öğeler',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.accentAmber,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final label
                          in session.sourceFeatures!.droppedFeatureLabels)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '• $label',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textLight,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: AppTheme.accentAmber,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Yöntem ve Güvenlik Sınırlamaları',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      AppConstants.rasterizationTradeOffNotice,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _understandTradeOffs,
                      activeColor: AppTheme.accentGreen,
                      onChanged: (val) {
                        setState(() {
                          _understandTradeOffs = val ?? false;
                        });
                      },
                      title: const Text(
                        'Yeni dosyada metin seçme, arama, ekran okuyucu desteği, formlar ve dijital imza olmayacağını anladım.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Çıktı Dosyası Adı',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Kaynak dosyadaki kişisel bilgileri taşımayan tarafsız dosya adı.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fileNameController,
                      style: const TextStyle(color: AppTheme.textLight),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF334155),
                          ),
                        ),
                        suffixText: '.pdf',
                        suffixStyle: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            ElevatedButton(
              onPressed: _understandTradeOffs && pages.isNotEmpty
                  ? _startProcessing
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Yeni PDF Oluştur ve Kontrol Et',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textLight,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
