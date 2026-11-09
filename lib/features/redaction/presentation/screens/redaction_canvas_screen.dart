import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_scan/core/theme/app_theme.dart';
import 'package:pure_scan/core/utils/coordinate_utils.dart';
import 'package:pure_scan/shared/models/redaction_area.dart';
import 'package:pure_scan/shared/providers/document_session_provider.dart';

enum CanvasInteractionMode { draw, panZoom }

enum _DragKind { none, drawing, moving, resizing }

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class RedactionCanvasScreen extends ConsumerStatefulWidget {
  const RedactionCanvasScreen({super.key});

  @override
  ConsumerState<RedactionCanvasScreen> createState() =>
      _RedactionCanvasScreenState();
}

class _RedactionCanvasScreenState extends ConsumerState<RedactionCanvasScreen> {
  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _imageKey = GlobalKey();
  CanvasInteractionMode _mode = CanvasInteractionMode.draw;

  String? _selectedAreaId;

  _DragKind _dragKind = _DragKind.none;
  _Corner? _activeCorner;
  Offset? _dragStart;
  Offset? _dragCurrent;
  Rect? _rectAtDragStart;

  static const double _minNormSize = 0.01;

  RenderBox? get _box =>
      _imageKey.currentContext?.findRenderObject() as RenderBox?;

  double get _zoom => _transformationController.value.getMaxScaleOnAxis();
  double get _handleTouchRadius => 26 / _zoom;
  double get _handleVisualSize => 16 / _zoom;

  RedactionArea? _areaById(List<RedactionArea> areas, String? id) =>
      id == null ? null : areas.where((a) => a.id == id).firstOrNull;

  Rect _toScreen(Rect normalized, Size size) =>
      CoordinateUtils.normalizedToScreen(
        normalizedRect: normalized,
        renderedBoxSize: size,
      );

  RedactionArea? _hitArea(Offset local, Size size, List<RedactionArea> areas) {
    for (final a in areas.reversed) {
      if (_toScreen(
        a.normalizedRect,
        size,
      ).inflate(4 / _zoom).contains(local)) {
        return a;
      }
    }
    return null;
  }

  _Corner? _hitCorner(Offset local, Rect screenRect) {
    final corners = {
      _Corner.topLeft: screenRect.topLeft,
      _Corner.topRight: screenRect.topRight,
      _Corner.bottomLeft: screenRect.bottomLeft,
      _Corner.bottomRight: screenRect.bottomRight,
    };
    for (final e in corners.entries) {
      if ((e.value - local).distance <= _handleTouchRadius) return e.key;
    }
    return null;
  }

  void _onTapUp(TapUpDetails details) {
    final box = _box;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final hit = _hitArea(
      local,
      box.size,
      ref.read(documentSessionProvider).activePageRedactions,
    );
    setState(() => _selectedAreaId = hit?.id);
  }

  void _onPanStart(DragStartDetails details) {
    final box = _box;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final areas = ref.read(documentSessionProvider).activePageRedactions;
    final notifier = ref.read(documentSessionProvider.notifier);

    final selected = _areaById(areas, _selectedAreaId);
    if (selected != null) {
      final corner = _hitCorner(
        local,
        _toScreen(selected.normalizedRect, box.size),
      );
      if (corner != null) {
        notifier.beginAreaEdit();
        setState(() {
          _dragKind = _DragKind.resizing;
          _activeCorner = corner;
          _dragStart = local;
          _rectAtDragStart = selected.normalizedRect;
        });
        return;
      }
    }

    final hit = _hitArea(local, box.size, areas);
    if (hit != null) {
      notifier.beginAreaEdit();
      setState(() {
        _selectedAreaId = hit.id;
        _dragKind = _DragKind.moving;
        _dragStart = local;
        _rectAtDragStart = hit.normalizedRect;
      });
      return;
    }

    setState(() {
      _selectedAreaId = null;
      _dragKind = _DragKind.drawing;
      _dragStart = local;
      _dragCurrent = local;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final box = _box;
    if (box == null || _dragStart == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final size = box.size;

    switch (_dragKind) {
      case _DragKind.drawing:
        setState(() => _dragCurrent = local);
      case _DragKind.moving:
        final start = _rectAtDragStart!;
        var dx = (local.dx - _dragStart!.dx) / size.width;
        var dy = (local.dy - _dragStart!.dy) / size.height;

        dx = dx.clamp(-start.left, 1.0 - start.right);
        dy = dy.clamp(-start.top, 1.0 - start.bottom);
        _updateSelected(start.shift(Offset(dx, dy)));
      case _DragKind.resizing:
        final start = _rectAtDragStart!;
        final nx = (local.dx / size.width).clamp(0.0, 1.0);
        final ny = (local.dy / size.height).clamp(0.0, 1.0);
        var l = start.left, t = start.top, r = start.right, b = start.bottom;
        switch (_activeCorner!) {
          case _Corner.topLeft:
            l = min(nx, r - _minNormSize);
            t = min(ny, b - _minNormSize);
          case _Corner.topRight:
            r = max(nx, l + _minNormSize);
            t = min(ny, b - _minNormSize);
          case _Corner.bottomLeft:
            l = min(nx, r - _minNormSize);
            b = max(ny, t + _minNormSize);
          case _Corner.bottomRight:
            r = max(nx, l + _minNormSize);
            b = max(ny, t + _minNormSize);
        }
        _updateSelected(Rect.fromLTRB(l, t, r, b));
      case _DragKind.none:
        break;
    }
  }

  void _updateSelected(Rect rect) {
    final id = _selectedAreaId;
    if (id == null) return;
    ref
        .read(documentSessionProvider.notifier)
        .updateRedactionAreaRect(id, rect);
  }

  void _onPanEnd(DragEndDetails details) {
    final notifier = ref.read(documentSessionProvider.notifier);
    if (_dragKind == _DragKind.drawing) {
      final box = _box;
      if (box != null && _dragStart != null && _dragCurrent != null) {
        final screenRect = Rect.fromPoints(_dragStart!, _dragCurrent!);

        if (screenRect.width * _zoom > 10 && screenRect.height * _zoom > 10) {
          notifier.addRedactionArea(
            CoordinateUtils.screenToNormalized(
              screenRect: screenRect,
              renderedBoxSize: box.size,
            ),
          );

          _selectedAreaId = ref
              .read(documentSessionProvider)
              .activePageRedactions
              .lastOrNull
              ?.id;
        }
      }
    } else if (_dragKind == _DragKind.moving ||
        _dragKind == _DragKind.resizing) {
      notifier.endAreaEdit();
    }
    setState(() {
      _dragKind = _DragKind.none;
      _activeCorner = null;
      _dragStart = null;
      _dragCurrent = null;
      _rectAtDragStart = null;
    });
  }

  void _deleteSelected() {
    final id = _selectedAreaId;
    if (id == null) return;
    ref.read(documentSessionProvider.notifier).removeRedactionArea(id);
    setState(() => _selectedAreaId = null);
  }

  void _goToPage(int index) {
    setState(() => _selectedAreaId = null);
    _transformationController.value = Matrix4.identity();
    ref.read(documentSessionProvider.notifier).setActivePageIndex(index);
  }

  @override
  void initState() {
    super.initState();

    _transformationController.addListener(() {
      if (mounted && _selectedAreaId != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(documentSessionProvider);
    final activePage = session.activePage;
    final redactions = session.activePageRedactions;
    final totalPages = session.pages.length;
    final currentIndex = session.activePageIndex;
    final notifier = ref.read(documentSessionProvider.notifier);

    if (_selectedAreaId != null &&
        _areaById(redactions, _selectedAreaId) == null) {
      _selectedAreaId = null;
    }

    if (activePage == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alan Seçimi')),
        body: const Center(child: Text('Sayfa bulunamadı')),
      );
    }

    final drawMode = _mode == CanvasInteractionMode.draw;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sayfa ${currentIndex + 1} / $totalPages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Geri al',
            onPressed: session.canUndo ? notifier.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'İleri al',
            onPressed: session.canRedo ? notifier.redo : null,
          ),
          IconButton(
            icon: const Icon(Icons.layers_clear_outlined),
            tooltip: 'Bu sayfadaki seçimleri temizle',
            onPressed: redactions.isNotEmpty
                ? () {
                    setState(() => _selectedAreaId = null);
                    notifier.clearActivePageRedactions();
                  }
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.surfaceDark,
            child: SegmentedButton<CanvasInteractionMode>(
              segments: const [
                ButtonSegment(
                  value: CanvasInteractionMode.draw,
                  icon: Icon(Icons.border_color, size: 18),
                  label: Text('Seç / Düzenle'),
                ),
                ButtonSegment(
                  value: CanvasInteractionMode.panZoom,
                  icon: Icon(Icons.zoom_in, size: 18),
                  label: Text('Yakınlaştır'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                _dragKind = _DragKind.none;
                _dragStart = null;
                _dragCurrent = null;
              }),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppTheme.primaryBlue,
                selectedForegroundColor: Colors.white,
                foregroundColor: AppTheme.textMuted,
              ),
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppTheme.primaryDark,
            child: _selectedAreaId != null
                ? Row(
                    children: [
                      const Icon(
                        Icons.open_with,
                        size: 16,
                        color: AppTheme.accentAmber,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Taşımak için sürükleyin, boyut için köşeleri çekin.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _deleteSelected,
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppTheme.accentRed,
                        ),
                        label: const Text(
                          'Sil',
                          style: TextStyle(color: AppTheme.accentRed),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selectedAreaId = null),
                        child: const Text('Tamam'),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      drawMode
                          ? 'Yeni alan için boş yere çizin. Değiştirmek için bir alana dokunun.'
                          : 'İki parmakla yakınlaştırın, tek parmakla kaydırın.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
          ),

          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              child: Center(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  panEnabled: !drawMode,
                  scaleEnabled: !drawMode,
                  minScale: 1.0,
                  maxScale: 6.0,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: GestureDetector(
                      onTapUp: drawMode ? _onTapUp : null,
                      onPanStart: drawMode ? _onPanStart : null,
                      onPanUpdate: drawMode ? _onPanUpdate : null,
                      onPanEnd: drawMode ? _onPanEnd : null,

                      child: AspectRatio(
                        aspectRatio: activePage.width / activePage.height,
                        child: Stack(
                          key: _imageKey,
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(activePage.currentImagePath),
                              key: ValueKey(activePage.currentImagePath),
                              fit: BoxFit.fill,
                              gaplessPlayback: false,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text(
                                  'Görüntü yüklenemedi',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final boxSize = Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  );
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      for (final area in redactions)
                                        _buildAreaWidget(
                                          area,
                                          boxSize,
                                          area.id == _selectedAreaId,
                                        ),
                                      if (_dragKind == _DragKind.drawing &&
                                          _dragStart != null &&
                                          _dragCurrent != null)
                                        _buildActiveDragWidget(),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceDark,
              border: Border(top: BorderSide(color: Color(0xFF334155))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: currentIndex > 0
                        ? () => _goToPage(currentIndex - 1)
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sayfa ${currentIndex + 1} / $totalPages',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textLight,
                          ),
                        ),
                        Text(
                          'Bu sayfada ${redactions.length} · toplam ${session.totalRedactionsCount} alan',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.accentGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios),
                    onPressed: currentIndex < totalPages - 1
                        ? () => _goToPage(currentIndex + 1)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _selectedAreaId = null);
                      context.push('/review');
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('İncele'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaWidget(RedactionArea area, Size boxSize, bool selected) {
    final r = _toScreen(area.normalizedRect, boxSize);
    final handle = _handleVisualSize;

    return Positioned(
      left: r.left - handle / 2,
      top: r.top - handle / 2,
      width: r.width + handle,
      height: r.height + handle,
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: handle / 2,
              top: handle / 2,
              width: r.width,
              height: r.height,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  border: Border.all(
                    color: selected ? AppTheme.accentAmber : AppTheme.accentRed,
                    width: (selected ? 2.5 : 2) / _zoom,
                  ),
                ),
              ),
            ),
            if (selected)
              for (final pos in [
                Offset.zero,
                Offset(r.width, 0),
                Offset(0, r.height),
                Offset(r.width, r.height),
              ])
                Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  width: handle,
                  height: handle,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.accentAmber,
                        width: 2 / _zoom,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveDragWidget() {
    final r = Rect.fromPoints(_dragStart!, _dragCurrent!);
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.accentRed.withValues(alpha: 0.35),
            border: Border.all(color: AppTheme.accentAmber, width: 2 / _zoom),
          ),
        ),
      ),
    );
  }
}
