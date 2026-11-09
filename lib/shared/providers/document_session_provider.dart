import 'dart:io';
import 'dart:ui';
import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import '../../core/security/temp_file_manager.dart';
import '../../core/utils/coordinate_utils.dart';
import '../models/redaction_area.dart';
import '../models/scanned_page.dart';
import '../services/image_processing_service.dart';
import '../services/image_sanitizer.dart';
import '../services/pdf_structure_inspector.dart';

typedef RedactionMap = Map<String, List<RedactionArea>>;

class SessionState {
  final Directory? sessionDir;
  final List<ScannedPage> pages;
  final int activePageIndex;
  final RedactionMap redactionsMap;
  final List<RedactionMap> undoStack;
  final List<RedactionMap> redoStack;
  final bool isLoading;
  final String? errorMessage;

  final SourcePdfFeatures? sourceFeatures;

  const SessionState({
    this.sessionDir,
    this.pages = const [],
    this.activePageIndex = 0,
    this.redactionsMap = const {},
    this.undoStack = const [],
    this.redoStack = const [],
    this.isLoading = false,
    this.errorMessage,
    this.sourceFeatures,
  });

  ScannedPage? get activePage =>
      pages.isNotEmpty && activePageIndex < pages.length
      ? pages[activePageIndex]
      : null;

  List<RedactionArea> get activePageRedactions => activePage != null
      ? (redactionsMap[activePage!.id] ?? const [])
      : const [];

  int get totalRedactionsCount =>
      pages.fold(0, (sum, p) => sum + (redactionsMap[p.id]?.length ?? 0));

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  SessionState copyWith({
    Directory? sessionDir,
    List<ScannedPage>? pages,
    int? activePageIndex,
    RedactionMap? redactionsMap,
    List<RedactionMap>? undoStack,
    List<RedactionMap>? redoStack,
    bool? isLoading,
    String? errorMessage,
    SourcePdfFeatures? sourceFeatures,
  }) {
    return SessionState(
      sessionDir: sessionDir ?? this.sessionDir,
      pages: pages ?? this.pages,
      activePageIndex: activePageIndex ?? this.activePageIndex,
      redactionsMap: redactionsMap ?? this.redactionsMap,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      sourceFeatures: sourceFeatures ?? this.sourceFeatures,
    );
  }
}

class DocumentSessionNotifier extends Notifier<SessionState> {
  static const Uuid _uuid = Uuid();

  @override
  SessionState build() => const SessionState();

  Future<void> initSession() async {
    if (state.sessionDir != null) {
      await TempFileManager.deleteSessionDirectory(state.sessionDir!);
    }
    final dir = await TempFileManager.createSessionDirectory();
    state = SessionState(sessionDir: dir);
  }

  Future<Directory> _ensureSessionDir() async {
    final existing = state.sessionDir;
    if (existing != null && await existing.exists()) return existing;
    final dir = await TempFileManager.createSessionDirectory();
    state = state.copyWith(sessionDir: dir);
    return dir;
  }

  void setActivePageIndex(int index) {
    if (index >= 0 && index < state.pages.length) {
      state = state.copyWith(activePageIndex: index);
    }
  }

  Future<void> addPageFromImage(
    File imageFile, {
    bool deleteSourceAfter = false,
  }) async {
    try {
      final sessionDir = await _ensureSessionDir();
      final pageId = _uuid.v4();
      final targetPath = TempFileManager.newPageImagePath(sessionDir, pageId);

      final clean = ImageSanitizer.decodeAndFlatten(
        await imageFile.readAsBytes(),
      );
      await ImageSanitizer.writePng(clean, targetPath);

      final newPage = ScannedPage(
        id: pageId,
        originalImagePath: targetPath,
        currentImagePath: targetPath,
        width: clean.width,
        height: clean.height,
        pageIndex: state.pages.length,
        qualityWarning: ImageSanitizer.assessQuality(clean),
      );

      state = state.copyWith(
        pages: [...state.pages, newPage],
        activePageIndex: state.pages.isEmpty ? 0 : state.activePageIndex,
      );
    } finally {
      if (deleteSourceAfter) {
        await TempFileManager.deleteIfPrivateTemp(imageFile.path);
      }
    }
  }

  void setPages(List<ScannedPage> pages, {SourcePdfFeatures? sourceFeatures}) {
    state = SessionState(
      sessionDir: state.sessionDir,
      pages: pages,
      sourceFeatures: sourceFeatures,
    );
  }

  Future<void> rotatePage(String pageId) async {
    final pageIndex = state.pages.indexWhere((p) => p.id == pageId);
    if (pageIndex == -1) return;
    final page = state.pages[pageIndex];

    final decoded = img.decodePng(
      await File(page.currentImagePath).readAsBytes(),
    );
    if (decoded == null) throw Exception('Sayfa görüntüsü okunamadı.');
    final rotated = img.copyRotate(decoded, angle: 90);

    final updatedPage = await _replacePageImage(
      page,
      rotated,
      page.copyWith(rotationDegrees: (page.rotationDegrees + 90) % 360),
    );

    _commitGeometryChange(
      pageIndex,
      updatedPage,
      (r) => CoordinateUtils.rotateNormalized90Clockwise(r),
    );
  }

  Future<void> cropPage(String pageId, Rect crop) async {
    final pageIndex = state.pages.indexWhere((p) => p.id == pageId);
    if (pageIndex == -1) return;
    final page = state.pages[pageIndex];

    final decoded = img.decodePng(
      await File(page.currentImagePath).readAsBytes(),
    );
    if (decoded == null) throw Exception('Sayfa görüntüsü okunamadı.');

    final x = (crop.left * decoded.width).floor().clamp(0, decoded.width - 1);
    final y = (crop.top * decoded.height).floor().clamp(0, decoded.height - 1);
    final r = (crop.right * decoded.width).ceil().clamp(x + 1, decoded.width);
    final b = (crop.bottom * decoded.height).ceil().clamp(
      y + 1,
      decoded.height,
    );
    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: r - x,
      height: b - y,
    );

    final pixelCrop = Rect.fromLTRB(
      x / decoded.width,
      y / decoded.height,
      r / decoded.width,
      b / decoded.height,
    );

    final quality = ImageSanitizer.assessQuality(cropped);
    final updatedPage = await _replacePageImage(
      page,
      cropped,
      page.copyWith(
        isCropped: true,
        qualityWarning: quality,
        clearQualityWarning: quality == null,
      ),
    );

    _commitGeometryChange(
      pageIndex,
      updatedPage,
      (rect) => CoordinateUtils.cropNormalized(rect, pixelCrop),
    );
  }

  Future<void> enhancePage(String pageId) async {
    final pageIndex = state.pages.indexWhere((p) => p.id == pageId);
    if (pageIndex == -1) return;
    final page = state.pages[pageIndex];
    if (page.isEnhanced) return;

    final decoded = img.decodePng(
      await File(page.currentImagePath).readAsBytes(),
    );
    if (decoded == null) throw Exception('Sayfa görüntüsü okunamadı.');
    final enhanced = ImageProcessingService.enhance(decoded);

    final updatedPage = await _replacePageImage(
      page,
      enhanced,
      page.copyWith(isEnhanced: true),
    );
    final pages = List<ScannedPage>.from(state.pages)
      ..[pageIndex] = updatedPage;
    state = state.copyWith(pages: pages);
  }

  Future<ScannedPage> _replacePageImage(
    ScannedPage page,
    img.Image newImage,
    ScannedPage base,
  ) async {
    final sessionDir = await _ensureSessionDir();
    final newPath = TempFileManager.newPageImagePath(sessionDir, page.id);
    await ImageSanitizer.writePng(newImage, newPath);

    final oldPath = page.currentImagePath;
    FileImage(File(oldPath)).evict();
    if (oldPath != page.originalImagePath) {
      try {
        await File(oldPath).delete();
      } catch (_) {}
    }
    return base.copyWith(
      currentImagePath: newPath,
      width: newImage.width,
      height: newImage.height,
    );
  }

  void _commitGeometryChange(
    int pageIndex,
    ScannedPage updatedPage,
    Rect? Function(Rect) transform,
  ) {
    final updatedPages = List<ScannedPage>.from(state.pages)
      ..[pageIndex] = updatedPage;
    final updatedRedactions = Map<String, List<RedactionArea>>.from(
      state.redactionsMap,
    );
    final current =
        updatedRedactions[updatedPage.id] ?? const <RedactionArea>[];
    updatedRedactions[updatedPage.id] = [
      for (final area in current)
        if (transform(area.normalizedRect) case final Rect r)
          area.copyWith(normalizedRect: r),
    ];

    state = state.copyWith(
      pages: updatedPages,
      redactionsMap: updatedRedactions,
      undoStack: [],
      redoStack: [],
    );
  }

  void reorderPages(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final updatedPages = List<ScannedPage>.from(state.pages);
    final item = updatedPages.removeAt(oldIndex);
    updatedPages.insert(newIndex, item);
    for (int i = 0; i < updatedPages.length; i++) {
      updatedPages[i] = updatedPages[i].copyWith(pageIndex: i);
    }

    state = state.copyWith(
      pages: updatedPages,
      activePageIndex: newIndex.clamp(0, updatedPages.length - 1),
    );
  }

  Future<void> removePage(String pageId) async {
    final removed = state.pages.where((p) => p.id == pageId).toList();
    final updatedPages = state.pages.where((p) => p.id != pageId).toList();
    for (int i = 0; i < updatedPages.length; i++) {
      updatedPages[i] = updatedPages[i].copyWith(pageIndex: i);
    }

    final updatedRedactions = Map<String, List<RedactionArea>>.from(
      state.redactionsMap,
    )..remove(pageId);

    final nextActive = updatedPages.isEmpty
        ? 0
        : state.activePageIndex.clamp(0, updatedPages.length - 1);

    state = state.copyWith(
      pages: updatedPages,
      activePageIndex: nextActive,
      redactionsMap: updatedRedactions,
      undoStack: [],
      redoStack: [],
    );

    for (final p in removed) {
      for (final path in {p.currentImagePath, p.originalImagePath}) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  void addRedactionArea(Rect normalizedRect) {
    final page = state.activePage;
    if (page == null) return;

    final undo = _pushHistory();
    final area = RedactionArea(
      id: _uuid.v4(),
      pageId: page.id,
      normalizedRect: normalizedRect,
      createdAt: DateTime.now(),
    );

    final updatedRedactions = Map<String, List<RedactionArea>>.from(
      state.redactionsMap,
    );
    updatedRedactions[page.id] = [
      ...(updatedRedactions[page.id] ?? const []),
      area,
    ];

    state = state.copyWith(
      redactionsMap: updatedRedactions,
      undoStack: undo,
      redoStack: [],
    );
  }

  void removeRedactionArea(String areaId) {
    final page = state.activePage;
    if (page == null) return;

    final undo = _pushHistory();
    final updatedRedactions = Map<String, List<RedactionArea>>.from(
      state.redactionsMap,
    );
    updatedRedactions[page.id] = (updatedRedactions[page.id] ?? const [])
        .where((a) => a.id != areaId)
        .toList();

    state = state.copyWith(
      redactionsMap: updatedRedactions,
      undoStack: undo,
      redoStack: [],
    );
  }

  RedactionMap? _editSnapshot;

  void beginAreaEdit() {
    _editSnapshot = state.redactionsMap;
  }

  void updateRedactionAreaRect(String areaId, Rect normalizedRect) {
    final page = state.activePage;
    if (page == null) return;
    final list = state.redactionsMap[page.id] ?? const <RedactionArea>[];
    if (!list.any((a) => a.id == areaId)) return;

    final updatedRedactions = Map<String, List<RedactionArea>>.from(
      state.redactionsMap,
    );
    updatedRedactions[page.id] = [
      for (final a in list)
        a.id == areaId ? a.copyWith(normalizedRect: normalizedRect) : a,
    ];
    state = state.copyWith(redactionsMap: updatedRedactions);
  }

  void endAreaEdit() {
    final snapshot = _editSnapshot;
    _editSnapshot = null;
    if (snapshot == null || identical(snapshot, state.redactionsMap)) return;
    final newUndo = [...state.undoStack, snapshot];
    if (newUndo.length > 30) newUndo.removeAt(0);
    state = state.copyWith(undoStack: newUndo, redoStack: []);
  }

  void clearActivePageRedactions() {
    final page = state.activePage;
    if (page == null) return;

    final undo = _pushHistory();
    final updatedRedactions = Map<String, List<RedactionArea>>.from(
      state.redactionsMap,
    );
    updatedRedactions[page.id] = [];

    state = state.copyWith(
      redactionsMap: updatedRedactions,
      undoStack: undo,
      redoStack: [],
    );
  }

  void undo() {
    if (state.undoStack.isEmpty) return;
    final previousMap = state.undoStack.last;
    state = state.copyWith(
      redactionsMap: previousMap,
      undoStack: List<RedactionMap>.from(state.undoStack)..removeLast(),
      redoStack: [...state.redoStack, state.redactionsMap],
    );
  }

  void redo() {
    if (state.redoStack.isEmpty) return;
    final nextMap = state.redoStack.last;
    state = state.copyWith(
      redactionsMap: nextMap,
      redoStack: List<RedactionMap>.from(state.redoStack)..removeLast(),
      undoStack: [...state.undoStack, state.redactionsMap],
    );
  }

  List<RedactionMap> _pushHistory() {
    final snapshot = state.redactionsMap.map(
      (k, v) => MapEntry(k, List<RedactionArea>.from(v)),
    );
    final newUndo = [...state.undoStack, snapshot];
    if (newUndo.length > 30) newUndo.removeAt(0);
    return newUndo;
  }

  Future<void> cancelSession() async {
    if (state.sessionDir != null) {
      await TempFileManager.deleteSessionDirectory(state.sessionDir!);
    }
    state = const SessionState();
  }
}

final documentSessionProvider =
    NotifierProvider<DocumentSessionNotifier, SessionState>(
      DocumentSessionNotifier.new,
    );
