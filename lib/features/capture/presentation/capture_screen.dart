import 'package:flutter/material.dart';

import 'package:microscopeapp/app_dependencies.dart';
import 'package:microscopeapp/features/capture/data/rear_camera_session.dart';
import 'package:microscopeapp/features/capture/presentation/capture_controller.dart';
import 'package:microscopeapp/features/capture/presentation/widgets/camera_stage.dart';
import 'package:microscopeapp/features/capture/presentation/widgets/capture_progress_panel.dart';
import 'package:microscopeapp/features/capture/presentation/widgets/frame_count_selector.dart';
import 'package:microscopeapp/features/capture/presentation/widgets/stability_notice.dart';
import 'package:microscopeapp/features/sessions/presentation/session_list_screen.dart';
import 'package:microscopeapp/features/sessions/presentation/session_summary_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CaptureController? _controller;
  var _leaving = false;

  CaptureController get controller => _controller!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final dependencies = AppScope.of(context);
    _controller = CaptureController(
      captureService: dependencies.captureService,
      openCamera: RearCameraSession.open,
    );
    controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final capture = _controller;
    if (capture == null || _leaving) {
      return;
    }
    final current = ModalRoute.of(context)?.isCurrent ?? false;
    if (!current) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        capture.initialize();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!capture.hasInitializedCamera) {
          return;
        }
        if (capture.isCapturing) {
          capture.interrupt();
          capture.releaseCamera();
        } else {
          capture.releaseCamera();
        }
      case AppLifecycleState.detached:
        capture.interrupt();
        capture.releaseCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final session = await controller.startCapture();
    if (!mounted || session == null) {
      return;
    }
    await _openRoute(SessionSummaryScreen(session: session));
  }

  Future<void> _openSessions() async {
    await _openRoute(const SessionListScreen());
  }

  Future<void> _openRoute(Widget page) async {
    _leaving = true;
    await controller.releaseCamera();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    _leaving = false;
    if (!mounted) {
      return;
    }
    await controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final capture = _controller;
    if (capture == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ListenableBuilder(
      listenable: capture,
      builder: (context, _) {
        final capturing = capture.isCapturing;
        return PopScope(
          canPop: !capturing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && capture.isCapturing) {
              capture.cancel();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 72,
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Crystal Scan'),
                  Text(
                    'Multi-frame capture',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Saved sessions',
                  onPressed: capturing ? null : _openSessions,
                  icon: const Icon(Icons.photo_library_outlined),
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    Expanded(
                      child: CameraStage(
                        phase: capture.phase,
                        controller: capture.previewController,
                        message: capture.message,
                        onRetry: capturing ? null : capture.initialize,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const StabilityNotice(),
                            if (capture.message != null &&
                                capture.phase == CapturePhase.ready) ...[
                              const SizedBox(height: 8),
                              Text(
                                capture.message!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            if (capturing) ...[
                              const SizedBox(height: 12),
                              CaptureProgressPanel(
                                progress: capture.progress,
                                setup: capture.cameraSetup,
                                stopping: capture.stopRequested,
                              ),
                            ],
                            const SizedBox(height: 12),
                            FrameCountSelector(
                              selected: capture.frameCount,
                              enabled: capture.canChangeSettings,
                              onChanged: capture.selectFrameCount,
                            ),
                            const SizedBox(height: 16),
                            _CaptureActions(
                              canCapture: capture.canChangeSettings,
                              capturing: capturing,
                              onCapture: _capture,
                              onCancel: capture.cancel,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CaptureActions extends StatelessWidget {
  const _CaptureActions({
    required this.canCapture,
    required this.capturing,
    required this.onCapture,
    required this.onCancel,
  });

  final bool canCapture;
  final bool capturing;
  final VoidCallback onCapture;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        SizedBox(
          width: 76,
          height: 76,
          child: FilledButton(
            style: FilledButton.styleFrom(shape: const CircleBorder()),
            onPressed: canCapture ? () => onCapture() : null,
            child: Icon(capturing ? Icons.hourglass_top : Icons.camera_alt, size: 32),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: capturing
                ? TextButton(onPressed: onCancel, child: const Text('Cancel'))
                : const SizedBox(width: 48),
          ),
        ),
      ],
    );
  }
}
