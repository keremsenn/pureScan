class ScannedPage {
  final String id;

  final String originalImagePath;

  final String currentImagePath;
  final int rotationDegrees;
  final int width;
  final int height;
  final int pageIndex;
  final bool isEnhanced;
  final bool isCropped;

  final double? sourceDpi;

  final String? qualityWarning;

  const ScannedPage({
    required this.id,
    required this.originalImagePath,
    required this.currentImagePath,
    this.rotationDegrees = 0,
    required this.width,
    required this.height,
    required this.pageIndex,
    this.isEnhanced = false,
    this.isCropped = false,
    this.sourceDpi,
    this.qualityWarning,
  });

  ScannedPage copyWith({
    String? id,
    String? originalImagePath,
    String? currentImagePath,
    int? rotationDegrees,
    int? width,
    int? height,
    int? pageIndex,
    bool? isEnhanced,
    bool? isCropped,
    double? sourceDpi,
    String? qualityWarning,
    bool clearQualityWarning = false,
  }) {
    return ScannedPage(
      id: id ?? this.id,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      currentImagePath: currentImagePath ?? this.currentImagePath,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      width: width ?? this.width,
      height: height ?? this.height,
      pageIndex: pageIndex ?? this.pageIndex,
      isEnhanced: isEnhanced ?? this.isEnhanced,
      isCropped: isCropped ?? this.isCropped,
      sourceDpi: sourceDpi ?? this.sourceDpi,
      qualityWarning: clearQualityWarning
          ? null
          : (qualityWarning ?? this.qualityWarning),
    );
  }
}
