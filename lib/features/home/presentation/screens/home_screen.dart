import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pure_scan/core/constants/app_constants.dart';
import 'package:pure_scan/core/security/privacy_logger.dart';
import 'package:pure_scan/core/theme/app_theme.dart';
import 'package:pure_scan/shared/providers/document_session_provider.dart';
import 'package:pdfx/pdfx.dart' show PdfDocument;
import 'package:pure_scan/core/security/temp_file_manager.dart';
import 'package:pure_scan/shared/services/image_sanitizer.dart';
import 'package:pure_scan/shared/services/pdf_rasterizer_service.dart';
import 'package:pure_scan/shared/services/pdf_structure_inspector.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isLoading = false;
  String? _loadingMessage;

  void _showError(String message, {Color color = AppTheme.accentRed}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _setLoading(bool value, [String? message]) {
    if (!mounted) return;
    setState(() {
      _isLoading = value;
      _loadingMessage = message;
    });
  }

  Future<void> _handleScanCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _showError('Kamera izni verilmedi. Belge taramak için izin gereklidir.');
      return;
    }

    await ref.read(documentSessionProvider.notifier).initSession();
    if (!mounted) return;
    context.push('/camera');
  }

  Future<String?> _askPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifreli PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dosya açılamadı. Şifreli ise şifresini girin.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Şifre'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Aç'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _handleOpenPdf() async {
    String? pickedPath;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      pickedPath = result.files.first.path;
      if (pickedPath == null) {
        _showError('Dosya okunamadı.');
        return;
      }

      final pdfFile = File(pickedPath);
      final fileSize = await pdfFile.length();
      if (fileSize > AppConstants.maxInputFileMb * 1024 * 1024) {
        _showError(
          'Dosya çok büyük. Bu sürüm en fazla ${AppConstants.maxInputFileMb} MB destekler.',
        );
        return;
      }

      _setLoading(true, 'PDF açılıyor...');

      PdfDocument doc;
      try {
        doc = await PdfRasterizerService.open(pdfFile);
      } on PdfOpenException catch (e) {
        if (!e.needsPassword) rethrow;
        _setLoading(false);
        final password = await _askPassword();
        if (password == null || password.isEmpty) {
          _showError(e.message);
          return;
        }
        _setLoading(true, 'PDF açılıyor...');
        doc = await PdfRasterizerService.open(pdfFile, password: password);
      }

      final sourceFeatures = PdfStructureInspector.detectSourceFeatures(
        await pdfFile.readAsBytes(),
      );

      final sessionNotifier = ref.read(documentSessionProvider.notifier);
      await sessionNotifier.initSession();
      final sessionDir = ref.read(documentSessionProvider).sessionDir!;

      try {
        final pages = await PdfRasterizerService.rasterizePdf(
          doc: doc,
          sessionDir: sessionDir,
          onProgress: (done, total) => _setLoading(
            true,
            'Sayfalar görüntüye dönüştürülüyor ($done / $total)...',
          ),
        );
        sessionNotifier.setPages(pages, sourceFeatures: sourceFeatures);
      } finally {
        await doc.close();
      }

      _setLoading(false);
      if (!mounted) return;
      context.push('/pages');
    } on PdfOpenException catch (e) {
      PrivacyLogger.logError('OPEN_PDF_FAILED', e);
      await ref.read(documentSessionProvider.notifier).cancelSession();
      _setLoading(false);
      _showError(e.message);
    } catch (e) {
      PrivacyLogger.logError('OPEN_PDF_FAILED', e);
      await ref.read(documentSessionProvider.notifier).cancelSession();
      _setLoading(false);
      _showError('PDF açılamadı. Dosya bozuk veya desteklenmiyor olabilir.');
    } finally {
      if (pickedPath != null) {
        try {
          await FilePicker.clearTemporaryFiles();
        } catch (_) {}
      }
    }
  }

  Future<void> _handleAddPhoto() async {
    try {
      final images = await ImagePicker().pickMultiImage();
      if (images.isEmpty) return;
      if (images.length > AppConstants.maxPages) {
        _showError('En fazla ${AppConstants.maxPages} sayfa eklenebilir.');
        for (final image in images) {
          await TempFileManager.deleteIfPrivateTemp(image.path);
        }
        return;
      }

      _setLoading(true, 'Fotoğraflar içe aktarılıyor...');

      final sessionNotifier = ref.read(documentSessionProvider.notifier);
      await sessionNotifier.initSession();
      for (final image in images) {
        await sessionNotifier.addPageFromImage(
          File(image.path),
          deleteSourceAfter: true,
        );
      }

      _setLoading(false);
      if (!mounted) return;
      context.push('/pages');
    } catch (e) {
      PrivacyLogger.logError('IMPORT_PHOTO_FAILED', e);
      await ref.read(documentSessionProvider.notifier).cancelSession();
      _setLoading(false);
      _showError(
        e is ImageImportException ? e.message : 'Fotoğraf eklenemedi.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shield_outlined,
              color: AppTheme.accentGreen,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(AppConstants.appName),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primaryBlue),
                  const SizedBox(height: 16),
                  Text(
                    _loadingMessage ?? 'İşleniyor...',
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.accentGreen.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.lock_outline,
                                color: AppTheme.accentGreen,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                AppConstants.appTagline,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: AppTheme.textLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Belgeleriniz cihazınızda işlenir; uygulama belgeyi bir sunucuya veya AI hizmetine göndermez. '
                          'Seçtiğiniz alanların pikselleri düz siyahla değiştirilir ve yeni bir PDF oluşturulur.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'Belge Ekle',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textLight,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildActionCard(
                    icon: Icons.camera_alt_outlined,
                    iconColor: AppTheme.primaryBlue,
                    title: 'Belge Tara',
                    subtitle: 'Kamerayla tek veya çok sayfalı belge tara',
                    onTap: _handleScanCamera,
                  ),

                  const SizedBox(height: 12),

                  _buildActionCard(
                    icon: Icons.picture_as_pdf_outlined,
                    iconColor: AppTheme.accentAmber,
                    title: 'PDF Aç',
                    subtitle:
                        'Cihazınızdaki mevcut bir PDF belgesini içe aktar',
                    onTap: _handleOpenPdf,
                  ),

                  const SizedBox(height: 12),

                  _buildActionCard(
                    icon: Icons.photo_library_outlined,
                    iconColor: AppTheme.accentGreen,
                    title: 'Fotoğraf Ekle',
                    subtitle: 'Galeriden belge fotoğraflarını seçip ekle',
                    onTap: _handleAddPhoto,
                  ),

                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NASIL ÇALIŞIR',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: AppTheme.accentGreen,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildSecurityItem(
                          icon: Icons.wifi_off_outlined,
                          text: 'İnternet olmadan cihazda çalışır',
                        ),
                        _buildSecurityItem(
                          icon: Icons.layers_clear_outlined,
                          text:
                              'Pikseller değiştirilir; üste siyah kutu konmaz',
                        ),
                        _buildSecurityItem(
                          icon: Icons.no_encryption_gmailerrorred_outlined,
                          text: 'Kaynak dosya değiştirilmez',
                        ),
                        _buildSecurityItem(
                          icon: Icons.verified_user_outlined,
                          text:
                              'Çıktı, teknik kontrolleri geçmeden paylaşılamaz',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppTheme.textLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityItem({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.accentGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
