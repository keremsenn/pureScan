class VerificationReport {
  final bool canOpen;
  final bool pageCountMatch;
  final int expectedPages;
  final int actualPages;

  final bool redactedAreasAreSolidBlack;
  final int totalAreasVerified;

  final bool noTextLayer;

  final bool noHiddenAttachments;

  final String sha256Digest;
  final String finalPdfPath;
  final int fileSize;

  final String? failureMessage;

  const VerificationReport({
    required this.canOpen,
    required this.pageCountMatch,
    required this.expectedPages,
    required this.actualPages,
    required this.redactedAreasAreSolidBlack,
    required this.totalAreasVerified,
    required this.noTextLayer,
    required this.noHiddenAttachments,
    required this.sha256Digest,
    required this.finalPdfPath,
    required this.fileSize,
    this.failureMessage,
  });

  VerificationReport withPath(String newPath) => VerificationReport(
    canOpen: canOpen,
    pageCountMatch: pageCountMatch,
    expectedPages: expectedPages,
    actualPages: actualPages,
    redactedAreasAreSolidBlack: redactedAreasAreSolidBlack,
    totalAreasVerified: totalAreasVerified,
    noTextLayer: noTextLayer,
    noHiddenAttachments: noHiddenAttachments,
    sha256Digest: sha256Digest,
    finalPdfPath: newPath,
    fileSize: fileSize,
    failureMessage: failureMessage,
  );

  bool get isPassed =>
      canOpen &&
      pageCountMatch &&
      redactedAreasAreSolidBlack &&
      noTextLayer &&
      noHiddenAttachments &&
      failureMessage == null;
}
