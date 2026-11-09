import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pure_scan/core/security/privacy_logger.dart';
import 'package:pure_scan/core/theme/app_theme.dart';
import 'package:pure_scan/shared/providers/document_session_provider.dart';

class CameraScanScreen extends ConsumerStatefulWidget {
  final bool appendMode;

  const CameraScanScreen({super.key, this.appendMode = false});

  @override
  ConsumerState<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends ConsumerState<CameraScanScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInit = false;
  bool _isCapturing = false;
  bool _flashOn = false;
  int _capturedCount = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanılabilir kamera bulunamadı.')),
        );
        context.pop();
        return;
      }

      final backCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isInit = true;
      });
    } catch (e) {
      PrivacyLogger.logError('CAMERA_INIT_FAILED', e);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kamera başlatılamadı.')));
      context.pop();
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInit) return;
    try {
      final newMode = _flashOn ? FlashMode.off : FlashMode.torch;
      await _controller!.setFlashMode(newMode);
      setState(() {
        _flashOn = !_flashOn;
      });
    } catch (e) {
      PrivacyLogger.logError('FLASH_TOGGLE_FAIL', e);
    }
  }

  Future<void> _capturePage() async {
    if (_controller == null || !_isInit || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final xFile = await _controller!.takePicture();

      await ref
          .read(documentSessionProvider.notifier)
          .addPageFromImage(File(xFile.path), deleteSourceAfter: true);
      if (!mounted) return;
      setState(() {
        _capturedCount++;
      });
    } catch (e) {
      PrivacyLogger.logError('PAGE_CAPTURE_FAIL', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf çekilemedi. Lütfen tekrar deneyin.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _finishScanning() {
    if (_capturedCount == 0 &&
        ref.read(documentSessionProvider).pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir sayfa tarayın.')),
      );
      return;
    }
    if (widget.appendMode) {
      context.pop();
    } else {
      context.pushReplacement('/pages');
    }
  }

  Future<void> _cancel() async {
    if (!widget.appendMode && ref.read(documentSessionProvider).pages.isEmpty) {
      await ref.read(documentSessionProvider.notifier).cancelSession();
    }
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryBlue),
        ),
      );
    }

    final totalPages = ref.watch(documentSessionProvider).pages.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _cancel,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Taranan: $totalPages Sayfa',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _flashOn ? Icons.flash_on : Icons.flash_off,
                        color: _flashOn ? AppTheme.accentAmber : Colors.white,
                      ),
                      onPressed: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black.withValues(alpha: 0.7),
              padding: const EdgeInsets.only(
                bottom: 32,
                top: 16,
                left: 24,
                right: 24,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  TextButton(
                    onPressed: _cancel,
                    child: const Text(
                      'İptal',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),

                  GestureDetector(
                    onTap: _isCapturing ? null : _capturePage,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _isCapturing
                            ? Colors.grey
                            : AppTheme.primaryBlue,
                      ),
                      child: _isCapturing
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 32,
                            ),
                    ),
                  ),

                  ElevatedButton(
                    onPressed: _finishScanning,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: totalPages > 0
                          ? AppTheme.accentGreen
                          : Colors.grey[800],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Tamam',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
}
