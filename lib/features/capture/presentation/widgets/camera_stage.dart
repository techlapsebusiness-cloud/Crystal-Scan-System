import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:microscopeapp/features/capture/presentation/capture_controller.dart';
import 'package:microscopeapp/features/capture/presentation/widgets/framing_guide.dart';

class CameraStage extends StatelessWidget {
  const CameraStage({
    super.key,
    required this.phase,
    required this.controller,
    required this.message,
    required this.onRetry,
  });

  final CapturePhase phase;
  final CameraController? controller;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final preview = controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF070C0C)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preview != null && preview.value.isInitialized)
              _CoveredPreview(controller: preview)
            else
              _StatusMessage(phase: phase, message: message, onRetry: onRetry),
            if (preview != null && preview.value.isInitialized) const FramingGuide(),
          ],
        ),
      ),
    );
  }
}

class _CoveredPreview extends StatelessWidget {
  const _CoveredPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.phase,
    required this.message,
    required this.onRetry,
  });

  final CapturePhase phase;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title) = switch (phase) {
      CapturePhase.opening => (Icons.photo_camera_outlined, 'Opening the rear camera'),
      CapturePhase.permissionDenied => (
        Icons.no_photography_outlined,
        'Camera permission is needed',
      ),
      CapturePhase.unavailable => (Icons.videocam_off_outlined, 'Rear camera unavailable'),
      CapturePhase.error => (Icons.error_outline, 'Camera error'),
      CapturePhase.ready || CapturePhase.capturing => (
        Icons.photo_camera_outlined,
        'Preparing the preview',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (phase == CapturePhase.opening)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: CircularProgressIndicator(),
              )
            else
              Icon(icon, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (onRetry != null && phase != CapturePhase.opening) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
