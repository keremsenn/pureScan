import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_scan/shared/models/scanned_page.dart';
import 'package:pure_scan/shared/providers/document_session_provider.dart';

void main() {
  late ProviderContainer container;
  late DocumentSessionNotifier notifier;
  SessionState state() => container.read(documentSessionProvider);

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(documentSessionProvider.notifier);
    notifier.setPages(const [
      ScannedPage(
        id: 'p1',
        originalImagePath: 'a',
        currentImagePath: 'a',
        width: 100,
        height: 100,
        pageIndex: 0,
      ),
      ScannedPage(
        id: 'p2',
        originalImagePath: 'b',
        currentImagePath: 'b',
        width: 100,
        height: 100,
        pageIndex: 1,
      ),
    ]);
  });
  tearDown(() => container.dispose());

  test('Birden fazla alan, birden fazla sayfada seçilebilir', () {
    notifier.addRedactionArea(const Rect.fromLTRB(0.1, 0.1, 0.2, 0.2));
    notifier.addRedactionArea(const Rect.fromLTRB(0.5, 0.5, 0.6, 0.6));
    notifier.setActivePageIndex(1);
    notifier.addRedactionArea(const Rect.fromLTRB(0.3, 0.3, 0.4, 0.4));
    expect(state().redactionsMap['p1'], hasLength(2));
    expect(state().redactionsMap['p2'], hasLength(1));
    expect(state().totalRedactionsCount, 3);
  });

  test('Seçim taşınabilir / boyutlandırılabilir ve tek adımda geri alınır', () {
    notifier.addRedactionArea(const Rect.fromLTRB(0.1, 0.1, 0.2, 0.2));
    final id = state().activePageRedactions.single.id;

    notifier.beginAreaEdit();
    notifier.updateRedactionAreaRect(
      id,
      const Rect.fromLTRB(0.15, 0.1, 0.25, 0.2),
    );
    notifier.updateRedactionAreaRect(
      id,
      const Rect.fromLTRB(0.3, 0.3, 0.4, 0.4),
    );
    notifier.endAreaEdit();
    expect(
      state().activePageRedactions.single.normalizedRect,
      const Rect.fromLTRB(0.3, 0.3, 0.4, 0.4),
    );

    notifier.beginAreaEdit();
    notifier.updateRedactionAreaRect(
      id,
      const Rect.fromLTRB(0.3, 0.3, 0.7, 0.5),
    );
    notifier.endAreaEdit();
    expect(
      state().activePageRedactions.single.normalizedRect.width,
      closeTo(0.4, 1e-9),
    );

    notifier.undo();
    expect(
      state().activePageRedactions.single.normalizedRect,
      const Rect.fromLTRB(0.3, 0.3, 0.4, 0.4),
    );
    notifier.undo();
    expect(
      state().activePageRedactions.single.normalizedRect,
      const Rect.fromLTRB(0.1, 0.1, 0.2, 0.2),
    );
    notifier.redo();
    expect(
      state().activePageRedactions.single.normalizedRect,
      const Rect.fromLTRB(0.3, 0.3, 0.4, 0.4),
    );
  });

  test('Hareket etmeyen dokunuş geçmişe boş adım eklemez', () {
    notifier.addRedactionArea(const Rect.fromLTRB(0.1, 0.1, 0.2, 0.2));
    final before = state().undoStack.length;
    notifier.beginAreaEdit();
    notifier.endAreaEdit();
    expect(state().undoStack.length, before);
  });

  test('Tek alan silinir, silme geri alınabilir', () {
    notifier.addRedactionArea(const Rect.fromLTRB(0.1, 0.1, 0.2, 0.2));
    notifier.addRedactionArea(const Rect.fromLTRB(0.5, 0.5, 0.6, 0.6));
    final first = state().activePageRedactions.first.id;
    notifier.removeRedactionArea(first);
    expect(state().activePageRedactions, hasLength(1));
    notifier.undo();
    expect(state().activePageRedactions, hasLength(2));
  });
}
