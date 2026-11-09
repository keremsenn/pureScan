import 'dart:ui';

class RedactionArea {
  final String id;
  final String pageId;
  final Rect normalizedRect;
  final DateTime createdAt;

  const RedactionArea({
    required this.id,
    required this.pageId,
    required this.normalizedRect,
    required this.createdAt,
  });

  RedactionArea copyWith({
    String? id,
    String? pageId,
    Rect? normalizedRect,
    DateTime? createdAt,
  }) {
    return RedactionArea(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      normalizedRect: normalizedRect ?? this.normalizedRect,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
