import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router/app_router.dart';
import 'core/constants/app_constants.dart';
import 'core/security/privacy_logger.dart';
import 'core/security/temp_file_manager.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await TempFileManager.performStartupCleanup();

  FlutterError.onError = (details) {
    PrivacyLogger.logError('FLUTTER_FRAMEWORK_ERROR', details.exception);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    PrivacyLogger.logError('UNCAUGHT_ASYNC_ERROR', error);
    return true;
  };

  runApp(const ProviderScope(child: PureScanApp()));
}

class PureScanApp extends StatefulWidget {
  const PureScanApp({super.key});

  @override
  State<PureScanApp> createState() => _PureScanAppState();
}

class _PureScanAppState extends State<PureScanApp> with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final obscure = state != AppLifecycleState.resumed;
    if (obscure != _obscured) setState(() => _obscured = obscure);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          if (_obscured)
            const Positioned.fill(
              child: ColoredBox(
                color: AppTheme.primaryDark,
                child: Center(
                  child: Icon(
                    Icons.shield_outlined,
                    size: 64,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
