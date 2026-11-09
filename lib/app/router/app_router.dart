import 'package:go_router/go_router.dart';
import '../../features/document_editor/presentation/screens/crop_page_screen.dart';
import '../../features/document_editor/presentation/screens/page_manager_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/processing/presentation/screens/processing_screen.dart';
import '../../features/redaction/presentation/screens/redaction_canvas_screen.dart';
import '../../features/redaction/presentation/screens/review_and_warning_screen.dart';
import '../../features/scanner/presentation/screens/camera_scan_screen.dart';
import '../../features/share/presentation/screens/result_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/camera',
      builder: (context, state) => CameraScanScreen(
        appendMode: state.uri.queryParameters['append'] == '1',
      ),
    ),
    GoRoute(
      path: '/pages',
      builder: (context, state) => const PageManagerScreen(),
    ),
    GoRoute(
      path: '/crop/:pageId',
      builder: (context, state) =>
          CropPageScreen(pageId: state.pathParameters['pageId']!),
    ),
    GoRoute(
      path: '/redaction',
      builder: (context, state) => const RedactionCanvasScreen(),
    ),
    GoRoute(
      path: '/review',
      builder: (context, state) => const ReviewAndWarningScreen(),
    ),
    GoRoute(
      path: '/processing',
      builder: (context, state) {
        final customFileName = state.extra as String?;
        return ProcessingScreen(customFileName: customFileName);
      },
    ),
    GoRoute(path: '/result', builder: (context, state) => const ResultScreen()),
  ],
);
