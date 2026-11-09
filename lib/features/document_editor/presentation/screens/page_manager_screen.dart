import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pure_scan/core/constants/app_constants.dart';
import 'package:pure_scan/core/security/privacy_logger.dart';
import 'package:pure_scan/core/security/temp_file_manager.dart';
import 'package:pure_scan/core/theme/app_theme.dart';
import 'package:pure_scan/shared/models/scanned_page.dart';
import 'package:pure_scan/shared/providers/document_session_provider.dart';
import 'package:pure_scan/shared/services/image_sanitizer.dart';

class PageManagerScreen extends ConsumerStatefulWidget {
  const PageManagerScreen({super.key});

  @override
  ConsumerState<PageManagerScreen> createState() => _PageManagerScreenState();
}

class _PageManagerScreenState extends ConsumerState<PageManagerScreen> {
  bool _busy = false;

  void _snack(String text, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  int get _remainingSlots =>
      AppConstants.maxPages - ref.read(documentSessionProvider).pages.length;

  Future<void> _run(Future<void> Function() action, String errorText) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      PrivacyLogger.logError('PAGE_EDIT_FAILED', e);
      _snack(
        e is ImageImportException ? e.message : errorText,
        color: AppTheme.accentRed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMoreFromGallery() async {
    final images = await ImagePicker().pickMultiImage();
    if (images.isEmpty) return;
    if (images.length > _remainingSlots) {
      _snack(
        'En fazla ${AppConstants.maxPages} sayfa eklenebilir.',
        color: AppTheme.accentAmber,
      );
      for (final i in images) {
        await TempFileManager.deleteIfPrivateTemp(i.path);
      }
      return;
    }
    await _run(() async {
      for (final imgFile in images) {
        await ref
            .read(documentSessionProvider.notifier)
            .addPageFromImage(File(imgFile.path), deleteSourceAfter: true);
      }
    }, 'Fotoğraf eklenemedi.');
  }

  Future<void> _addFromCamera() async {
    if (_remainingSlots <= 0) {
      _snack(
        'En fazla ${AppConstants.maxPages} sayfa eklenebilir.',
        color: AppTheme.accentAmber,
      );
      return;
    }
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _snack('Kamera izni verilmedi.', color: AppTheme.accentRed);
      return;
    }
    if (!mounted) return;
    context.push('/camera?append=1');
  }

  void _proceedToRedaction() {
    final session = ref.read(documentSessionProvider);
    if (session.pages.isEmpty) {
      _snack('Lütfen en az bir sayfa ekleyin.');
      return;
    }
    context.push('/redaction');
  }

  Future<bool> _confirmLeave() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Belgeden çıkılsın mı?'),
        content: const Text(
          'Çalışma kopyaları ve seçimleriniz silinecek. Orijinal belgeniz değişmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(documentSessionProvider);
    final pages = session.pages;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave()) {
          await ref.read(documentSessionProvider.notifier).cancelSession();
          if (context.mounted) context.go('/');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Sayfaları Düzenle (${pages.length})'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: 'Galeriden sayfa ekle',
              onPressed: _busy ? null : _addMoreFromGallery,
            ),
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined),
              tooltip: 'Kamerayla sayfa ekle',
              onPressed: _busy ? null : _addFromCamera,
            ),
          ],
        ),
        body: pages.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 64,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Henüz sayfa eklenmedi',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _addFromCamera,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Sayfa Tara'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: AppTheme.surfaceDark,
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: AppTheme.accentGreen,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sayfaları sürükleyerek sıralayın. Kırpma, döndürme ve okunurluk için ⋮ menüsünü kullanın.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: pages.length,
                      onReorder: (oldIndex, newIndex) {
                        ref
                            .read(documentSessionProvider.notifier)
                            .reorderPages(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final page = pages[index];
                        return _buildPageCard(
                          page,
                          index,
                          session.redactionsMap[page.id]?.length ?? 0,
                          key: ValueKey(page.id),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: AppTheme.surfaceDark,
                      border: Border(top: BorderSide(color: Color(0xFF334155))),
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _proceedToRedaction,
                          icon: const Icon(Icons.shield_outlined),
                          label: Text(
                            'Kaldırılacak Alanları Seç (${pages.length} Sayfa)',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPageCard(
    ScannedPage page,
    int index,
    int selectionCount, {
    required Key key,
  }) {
    final notifier = ref.read(documentSessionProvider.notifier);
    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 60,
                height: 80,
                child: Image.file(
                  File(page.currentImagePath),
                  fit: BoxFit.contain,
                  cacheWidth: 180,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.black26,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sayfa ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.textLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${page.width} × ${page.height} px'
                    '${selectionCount > 0 ? ' · $selectionCount seçim' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  if (page.qualityWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: AppTheme.accentAmber,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              page.qualityWarning!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.accentAmber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (value) async {
                switch (value) {
                  case 'rotate':
                    await _run(
                      () => notifier.rotatePage(page.id),
                      'Sayfa döndürülemedi.',
                    );
                  case 'crop':
                    context.push('/crop/${page.id}');
                  case 'enhance':
                    await _run(
                      () => notifier.enhancePage(page.id),
                      'Okunurluk iyileştirilemedi.',
                    );
                  case 'delete':
                    await _run(
                      () => notifier.removePage(page.id),
                      'Sayfa silinemedi.',
                    );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rotate', child: Text('90° döndür')),
                const PopupMenuItem(
                  value: 'crop',
                  child: Text('Kenarları kırp'),
                ),
                PopupMenuItem(
                  value: 'enhance',
                  enabled: !page.isEnhanced,
                  child: Text(
                    page.isEnhanced
                        ? 'Okunurluk iyileştirildi'
                        : 'Okunurluğu iyileştir',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Sayfayı sil',
                    style: TextStyle(color: AppTheme.accentRed),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
