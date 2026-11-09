import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_scan/core/constants/app_constants.dart';
import 'package:pure_scan/main.dart';

void main() {
  testWidgets('PureScanApp smoke test loads home screen with action buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PureScanApp()));
    await tester.pumpAndSettle();

    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text('Belge Tara'), findsOneWidget);
    expect(find.text('PDF Aç'), findsOneWidget);
    expect(find.text('Fotoğraf Ekle'), findsOneWidget);
  });
}
