import 'dart:math';
import 'dart:ui';
import '../constants/app_constants.dart';

class PixelRedactionBounds {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const PixelRedactionBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  int get width => right - left;
  int get height => bottom - top;
}

class CoordinateUtils {
  CoordinateUtils._();

  static PixelRedactionBounds toPixelBounds({
    required Rect normalizedRect,
    required int imageWidth,
    required int imageHeight,
    int securityMargin = AppConstants.redactionSecurityMarginPx,
  }) {
    final nLeft = normalizedRect.left.clamp(0.0, 1.0);
    final nTop = normalizedRect.top.clamp(0.0, 1.0);
    final nRight = normalizedRect.right.clamp(0.0, 1.0);
    final nBottom = normalizedRect.bottom.clamp(0.0, 1.0);

    var pLeft = (nLeft * imageWidth).floor() - securityMargin;
    var pTop = (nTop * imageHeight).floor() - securityMargin;
    var pRight = (nRight * imageWidth).ceil() + securityMargin;
    var pBottom = (nBottom * imageHeight).ceil() + securityMargin;

    pLeft = max(0, min(imageWidth - 1, pLeft));
    pTop = max(0, min(imageHeight - 1, pTop));
    pRight = max(pLeft + 1, min(imageWidth, pRight));
    pBottom = max(pTop + 1, min(imageHeight, pBottom));

    return PixelRedactionBounds(
      left: pLeft,
      top: pTop,
      right: pRight,
      bottom: pBottom,
    );
  }

  static Rect screenToNormalized({
    required Rect screenRect,
    required Size renderedBoxSize,
  }) {
    if (renderedBoxSize.width <= 0 || renderedBoxSize.height <= 0) {
      return Rect.zero;
    }
    final left = (screenRect.left / renderedBoxSize.width).clamp(0.0, 1.0);
    final top = (screenRect.top / renderedBoxSize.height).clamp(0.0, 1.0);
    final right = (screenRect.right / renderedBoxSize.width).clamp(0.0, 1.0);
    final bottom = (screenRect.bottom / renderedBoxSize.height).clamp(0.0, 1.0);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Rect rotateNormalized90Clockwise(Rect r) {
    return Rect.fromLTRB(1.0 - r.bottom, r.left, 1.0 - r.top, r.right);
  }

  static Rect? cropNormalized(Rect r, Rect crop) {
    final clipped = r.intersect(crop);
    if (clipped.width <= 0 || clipped.height <= 0) return null;
    return Rect.fromLTRB(
      ((clipped.left - crop.left) / crop.width).clamp(0.0, 1.0),
      ((clipped.top - crop.top) / crop.height).clamp(0.0, 1.0),
      ((clipped.right - crop.left) / crop.width).clamp(0.0, 1.0),
      ((clipped.bottom - crop.top) / crop.height).clamp(0.0, 1.0),
    );
  }

  static Size outputPageSizePts({
    required int pixelWidth,
    required int pixelHeight,
    double? sourceDpi,
  }) {
    final double scale;
    if (sourceDpi != null && sourceDpi > 0) {
      scale = 72.0 / sourceDpi;
    } else {
      scale = 842.0 / max(pixelWidth, pixelHeight);
    }

    return Size(
      max(1, (pixelWidth * scale).round()).toDouble(),
      max(1, (pixelHeight * scale).round()).toDouble(),
    );
  }

  static Rect normalizedToScreen({
    required Rect normalizedRect,
    required Size renderedBoxSize,
  }) {
    return Rect.fromLTRB(
      normalizedRect.left * renderedBoxSize.width,
      normalizedRect.top * renderedBoxSize.height,
      normalizedRect.right * renderedBoxSize.width,
      normalizedRect.bottom * renderedBoxSize.height,
    );
  }
}
