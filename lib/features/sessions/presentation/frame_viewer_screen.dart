import 'dart:io';

import 'package:flutter/material.dart';

import 'package:microscopeapp/core/utils/formatters.dart';
import 'package:microscopeapp/models/frame_record.dart';

class FrameViewerScreen extends StatelessWidget {
  const FrameViewerScreen({super.key, required this.frame});

  final FrameRecord frame;

  @override
  Widget build(BuildContext context) {
    final path = frame.filePath;
    final file = path == null ? null : File(path);
    final image = file != null && file.existsSync()
        ? InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const _MissingFrame(
                    message: 'This frame could not be decoded.',
                  );
                },
              ),
            ),
          )
        : const _MissingFrame(message: 'This frame file is not on disk.');
    return Scaffold(
      appBar: AppBar(title: Text('Frame ${frame.frameNumber}')),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF070C0C),
              child: image,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(frame.fileName, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _line('Captured', formatTimestamp(frame.capturedAt)),
                  _line(
                    'Dimensions',
                    frame.width == null || frame.height == null
                        ? 'Not recorded'
                        : '${frame.width}×${frame.height}',
                  ),
                  _line(
                    'File size',
                    frame.fileSizeBytes == null
                        ? 'Not recorded'
                        : formatBytes(frame.fileSizeBytes!),
                  ),
                  _line('Focus', frame.focusMode ?? 'Not exposed by the camera'),
                  _line('Exposure', frame.exposureMode ?? 'Not exposed by the camera'),
                  _line('Flash', frame.flashMode ?? 'Not exposed by the camera'),
                  _line(
                    'Exposure offset',
                    frame.exposureOffset == null
                        ? 'Not exposed by the camera'
                        : '${frame.exposureOffset}',
                  ),
                  if (!frame.success && frame.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(frame.error!),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $value'),
    );
  }
}

class _MissingFrame extends StatelessWidget {
  const _MissingFrame({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
