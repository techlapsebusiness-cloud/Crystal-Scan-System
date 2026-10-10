import 'package:flutter/material.dart';

import 'package:microscopeapp/app_dependencies.dart';
import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/core/utils/formatters.dart';
import 'package:microscopeapp/features/reconstruction/presentation/reconstruction_screen.dart';
import 'package:microscopeapp/features/sessions/presentation/frame_viewer_screen.dart';
import 'package:microscopeapp/features/sessions/presentation/widgets/session_stat.dart';
import 'package:microscopeapp/features/sessions/presentation/widgets/thumbnail_grid.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/session_status.dart';

class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({super.key, required this.session});

  final CaptureSession session;

  @override
  Widget build(BuildContext context) {
    final saved = session.savedFrames;
    final capturedSize = session.capturedSizeLabel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture session'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _StatusChip(status: session.status)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.id, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(formatTimestamp(session.createdAt)),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 700 ? 3 : 2;
                            final tileWidth =
                                (constraints.maxWidth - (columns - 1) * 8) / columns;
                            final stats = [
                              SessionStat(
                                label: 'Requested',
                                value: '${session.requestedFrameCount}',
                              ),
                              SessionStat(label: 'Saved', value: '${session.savedCount}'),
                              SessionStat(label: 'Failed', value: '${session.failedCount}'),
                              SessionStat(
                                label: 'Not attempted',
                                value: '${session.notAttempted}',
                              ),
                              SessionStat(
                                label: 'Duration',
                                value: formatDuration(session.elapsed),
                              ),
                              SessionStat(
                                label: 'Frame size',
                                value: capturedSize ?? '—',
                              ),
                            ];
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final stat in stats)
                                  SizedBox(width: tileWidth, child: stat),
                              ],
                            );
                          },
                        ),
                        if (session.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            session.errorMessage!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text('Storage directory', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        SelectableText(session.directoryPath),
                        if (session.camera != null) ...[
                          const SizedBox(height: 16),
                          Text('Camera', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(session.camera!.cameraName),
                          Text(session.camera!.lockSummary),
                          Text(
                            'Requested preset: ${session.camera!.requestedResolution}. '
                            'The JPEG dimensions above are the actual captured size.',
                          ),
                          if (session.camera!.previewWidth != null &&
                              session.camera!.previewHeight != null)
                            Text(
                              'Preview size reported by the camera: '
                              '${session.camera!.previewWidth}×${session.camera!.previewHeight}',
                            ),
                          if (session.camera!.limitations.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            for (final limitation in session.camera!.limitations)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('• $limitation'),
                              ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        Text(
                          saved.isEmpty ? 'No frames were saved.' : 'Original frames',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (saved.isNotEmpty)
                  ThumbnailGrid(
                    frames: saved,
                    onOpen: (frame) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FrameViewerScreen(frame: frame),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: () {
                      final processing = AppScope.of(context).processing;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReconstructionScreen(
                            session: session,
                            processing: processing,
                          ),
                        ),
                      );
                    },
                    child: const Text('Continue to reconstruction'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text('Recapture'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => _confirmDelete(context),
                    style: TextButton.styleFrom(foregroundColor: crystalDanger),
                    child: const Text('Delete session'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete session?'),
          content: const Text(
            'Delete this session and its original frames? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: crystalDanger,
                foregroundColor: const Color(0xFF2A0A12),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await AppScope.of(context).store.deleteSession(session.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1C3331),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(sessionStatusLabel(status)),
      ),
    );
  }
}
