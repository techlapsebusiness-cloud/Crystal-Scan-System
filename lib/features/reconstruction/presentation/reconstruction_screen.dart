import 'package:flutter/material.dart';

import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/services/image_processing_service.dart';

const List<ReconstructionStage> _pipeline = [
  ReconstructionStage.preparing,
  ReconstructionStage.aligning,
  ReconstructionStage.reconstructing,
  ReconstructionStage.saving,
];

class ReconstructionScreen extends StatefulWidget {
  const ReconstructionScreen({
    super.key,
    required this.session,
    required this.processing,
  });

  final CaptureSession session;
  final ImageProcessingService processing;

  @override
  State<ReconstructionScreen> createState() => _ReconstructionScreenState();
}

class _ReconstructionScreenState extends State<ReconstructionScreen> {
  ReconstructionStage _stage = ReconstructionStage.notStarted;
  ReconstructionResult? _result;

  Future<void> _run() async {
    final paths = [
      for (final frame in widget.session.savedFrames)
        if (frame.filePath != null) frame.filePath!,
    ];
    final result = await widget.processing.reconstruct(
      ReconstructionRequest(
        sessionId: widget.session.id,
        originalImagePaths: paths,
        outputDirectory: '${widget.session.directoryPath}/output',
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _result = result;
      _stage = result.stage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final savedCount = widget.session.savedCount;
    final canRun = savedCount > 0 && _stage == ReconstructionStage.notStarted;
    return Scaffold(
      appBar: AppBar(title: const Text('Reconstruction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reconstructionStageLabel(_stage),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: crystalTeal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result?.message ??
                        'The reconstruction engine is not connected. Running it will not create an image or move a progress bar.',
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 8),
                    Text('Engine: ${result.algorithmName} ${result.algorithmVersion}'),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: canRun ? _run : null,
                      child: Text(
                        savedCount == 0 ? 'No saved frames' : 'Run reconstruction',
                      ),
                    ),
                  ),
                  if (savedCount == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Capture at least one frame before reconstruction can be attempted.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Pipeline', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final stage in _pipeline)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _stageCompleted(stage) ? Icons.check_circle : Icons.circle_outlined,
                color: _stageCompleted(stage) ? crystalTeal : theme.colorScheme.onSurface,
              ),
              title: Text(reconstructionStageLabel(stage)),
            ),
          const SizedBox(height: 8),
          Text(
            'A later engine is intended to estimate one sharper image from the saved frames using y_i = D(H_i x) + n_i. It must not invent circuit traces. This version does not run that process.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Output', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _Fact(label: 'Original frames available', value: '$savedCount'),
          _Fact(
            label: 'Reconstructed image',
            value: result?.outputFilePath ?? 'Not available',
          ),
          _Fact(
            label: 'Before/after comparison',
            value: result?.outputFilePath == null ? 'Not available' : 'Output file is ready to compare',
          ),
          _Fact(
            label: 'Output dimensions',
            value: result?.outputWidth == null || result?.outputHeight == null
                ? 'Not available'
                : '${result!.outputWidth}×${result.outputHeight} pixels',
          ),
          _Fact(
            label: 'Frames used',
            value: result == null
                ? 'Not available'
                : '${result.framesAccepted} accepted, ${result.framesRejected} rejected, ${result.inputFrameCount} provided',
          ),
          _Fact(
            label: 'Effective resolution',
            value: result?.effectiveResolution ?? ReconstructionResult.notMeasuredResolution,
          ),
          const _Fact(
            label: 'Export PNG or TIFF',
            value: 'Not available until a reconstruction file exists. Originals are never replaced.',
          ),
        ],
        ),
      ),
    );
  }

  bool _stageCompleted(ReconstructionStage stage) {
    if (_stage != ReconstructionStage.completed) {
      return false;
    }
    return _pipeline.contains(stage);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}
