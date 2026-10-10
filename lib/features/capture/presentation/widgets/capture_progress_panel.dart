import 'package:flutter/material.dart';

import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/core/utils/formatters.dart';
import 'package:microscopeapp/models/camera_setup.dart';
import 'package:microscopeapp/models/capture_progress.dart';

class CaptureProgressPanel extends StatelessWidget {
  const CaptureProgressPanel({
    super.key,
    required this.progress,
    this.setup,
    this.stopping = false,
  });

  final CaptureProgress progress;
  final CameraSetup? setup;
  final bool stopping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frameLabel = progress.currentFrame <= 0
        ? 'Frame — of ${progress.requested}'
        : 'Frame ${progress.currentFrame} of ${progress.requested}';
    return Semantics(
      label: 'Capture progress',
      value:
          '${progress.percent} percent, ${progress.saved} of ${progress.requested} frames saved',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${progress.percent}%',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: crystalTeal,
                ),
              ),
              const Spacer(),
              Text(
                formatDuration(progress.elapsed),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 8,
              backgroundColor: const Color(0xFF243332),
            ),
          ),
          const SizedBox(height: 8),
          Text('${progress.saved} / ${progress.requested} saved'),
          const SizedBox(height: 2),
          Text('$frameLabel · Failed ${progress.failed}'),
          if (stopping) ...[
            const SizedBox(height: 6),
            Text(
              'Finishing the current frame…',
              style: theme.textTheme.bodyMedium?.copyWith(color: crystalWarning),
            ),
          ],
          if (setup != null) ...[
            const SizedBox(height: 6),
            Text(setup!.lockSummary, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
