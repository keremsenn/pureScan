import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_scan/core/security/privacy_logger.dart';
import 'package:pure_scan/core/theme/app_theme.dart';
import 'package:pure_scan/core/utils/coordinate_utils.dart';
import 'package:pure_scan/shared/providers/document_session_provider.dart';

class CropPageScreen extends ConsumerStatefulWidget {
  final String pageId;
  const CropPageScreen({super.key, required this.pageId});

  @override
  ConsumerState<CropPageScreen> createState() => _CropPageScreenState();
}

class _CropPageScreenState extends ConsumerState<CropPageScreen> {
  final GlobalKey _boxKey = GlobalKey();
  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1);
  Offset? _start;
  bool _busy = false;

  Offset? _toNormalized(Offset global) {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return null;
    final local = box.globalToLocal(global);
    return Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
  }

  Future<void> _apply() async {
    if (_crop.width < 0.05 || _crop.height < 0.05) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kırpma alanı çok küçük.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(documentSessionProvider.notifier)
          .cropPage(widget.pageId, _crop);
      if (mounted) context.pop();
    } catch (e) {
      PrivacyLogger.logError('CROP_FAILED', e);
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sayfa kırpılamadı.'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(documentSessionProvider);
    final page = session.pages.where((p) => p.id == widget.pageId).firstOrNull;

    if (page == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kırp')),
        body: const Center(child: Text('Sayfa bulunamadı')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sayfa kenarlarını belirle'),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _crop = const Rect.fromLTRB(0, 0, 1, 1)),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: AppTheme.surfaceDark,
            child: const Text(
              'Belgenin kalmasını istediğiniz alanı parmağınızla çizin. '
              'Bu sayfadaki seçimler yeni kenarlara göre taşınır.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AspectRatio(
                  aspectRatio: page.width / page.height,
                  child: GestureDetector(
                    onPanStart: (d) {
                      final n = _toNormalized(d.globalPosition);
                      if (n == null) return;
                      setState(() {
                        _start = n;
                        _crop = Rect.fromPoints(n, n);
                      });
                    },
                    onPanUpdate: (d) {
                      final n = _toNormalized(d.globalPosition);
                      if (n == null || _start == null) return;
                      setState(() => _crop = Rect.fromPoints(_start!, n));
                    },
                    onPanEnd: (_) => _start = null,
                    child: Stack(
                      key: _boxKey,
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(page.currentImagePath),
                          fit: BoxFit.fill,
                        ),
                        LayoutBuilder(
                          builder: (context, c) {
                            final size = Size(c.maxWidth, c.maxHeight);
                            final r = CoordinateUtils.normalizedToScreen(
                              normalizedRect: _crop,
                              renderedBoxSize: size,
                            );
                            return CustomPaint(painter: _CropPainter(r));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _apply,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.crop),
                  label: const Text('Kırp'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect rect;
  _CropPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      shade,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppTheme.accentGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}
