import 'dart:io';

import 'package:flutter/material.dart';

import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/features/results/presentation/results_screen.dart';
import 'package:microscopeapp/models/capture_session.dart';
import 'package:microscopeapp/models/reconstruction_result.dart';
import 'package:microscopeapp/services/image_processing_service.dart';

const List<ReconstructionStage> _unavailablePipeline = [
  ReconstructionStage.preparing,
  ReconstructionStage.aligning,
  ReconstructionStage.reconstructing,
  ReconstructionStage.saving,
];

const List<ReconstructionStage> _livePipeline = [
  ReconstructionStage.preparing,
  ReconstructionStage.analyzing,
  ReconstructionStage.selectingReference,
  ReconstructionStage.estimatingMotion,
  ReconstructionStage.aligning,
  ReconstructionStage.rejecting,
  ReconstructionStage.denoising,
  ReconstructionStage.superResolving,
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
  ReconstructionCancellation? _cancellation;
  var _running = false;
  var _completed = 0;
  var _total = 0;
  var _accepted = 0;
  var _rejected = 0;
  var _detail = '';
  var _allowSuperResolution = true;
  var _rejectOutliers = true;

  Future<void> _run() async {
    final paths = [
      for (final frame in widget.session.savedFrames)
        if (frame.filePath != null) frame.filePath!,
    ];
    if (!widget.processing.isAvailable) {
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
      return;
    }

    final cancellation = ReconstructionCancellation();
    setState(() {
      _running = true;
      _result = null;
      _stage = ReconstructionStage.preparing;
      _completed = 0;
      _total = paths.length;
      _accepted = 0;
      _rejected = 0;
      _detail = '';
      _cancellation = cancellation;
    });
    final result = await widget.processing.reconstruct(
      ReconstructionRequest(
        sessionId: widget.session.id,
        originalImagePaths: paths,
        outputDirectory: '${widget.session.directoryPath}/results',
        options: ReconstructionOptions(
          allowSuperResolution: _allowSuperResolution,
          rejectOutliers: _rejectOutliers,
        ),
      ),
      onProgress: (progress) {
        if (!mounted) {
          return;
        }
        setState(() {
          _stage = progress.stage;
          _completed = progress.completed;
          _total = progress.total;
          _accepted = progress.framesAccepted;
          _rejected = progress.framesRejected;
          _detail = progress.detail;
        });
      },
      cancellation: cancellation,
    );
    if (!mounted) {
      return;
    }
    final output = result.outputFilePath;
    final saved = result.success &&
        output != null &&
        File(output).existsSync() &&
        File(output).lengthSync() > 0;
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _cancellation = null;
      _result = saved
          ? result
          : ReconstructionResult(
              implemented: result.implemented,
              success: false,
              stage: result.stage == ReconstructionStage.completed
                  ? ReconstructionStage.failed
                  : result.stage,
              outputFilePath: saved ? result.outputFilePath : null,
              outputWidth: saved ? result.outputWidth : result.outputWidth,
              outputHeight: saved ? result.outputHeight : result.outputHeight,
              inputFrameCount: result.inputFrameCount,
              framesAccepted: result.framesAccepted,
              framesRejected: result.framesRejected,
              processingDuration: result.processingDuration,
              algorithmName: result.algorithmName,
              algorithmVersion: result.algorithmVersion,
              qualityMetrics: result.qualityMetrics,
              message: saved
                  ? result.message
                  : result.success
                      ? 'The reconstruction reported success, but the output file is missing. Nothing is shown as complete.'
                      : result.message,
              effectiveResolution: result.effectiveResolution,
              superResolutionPerformed: saved && result.superResolutionPerformed,
              strategy: result.strategy,
              referenceFramePath: result.referenceFramePath,
              inputWidth: result.inputWidth,
              inputHeight: result.inputHeight,
              scaleFactor: result.scaleFactor,
              warnings: result.warnings,
              frameReports: result.frameReports,
              inputFramePaths: result.inputFramePaths,
              denoisedFilePath: saved ? result.denoisedFilePath : null,
              superResolutionFilePath: saved ? result.superResolutionFilePath : null,
              metadataFilePath: result.metadataFilePath,
            );
      _stage = _result!.stage;
      _accepted = result.framesAccepted;
      _rejected = result.framesRejected;
    });
    if (!saved || !mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResultsScreen(sessionId: widget.session.id, result: result),
      ),
    );
  }

  Future<void> _showOptions() async {
    var allow = _allowSuperResolution;
    var outliers = _rejectOutliers;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Advanced settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow super-resolution'),
                    subtitle: const Text(
                      'Uses a 2× grid only when frames have a measured subpixel shift and the output fits the pixel budget.',
                    ),
                    value: allow,
                    onChanged: (value) => setDialogState(() => allow = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reject outlier pixels'),
                    subtitle: const Text(
                      'Leaves out pixels that disagree with the reference, which limits ghosting from a moving object.',
                    ),
                    value: outliers,
                    onChanged: (value) => setDialogState(() => outliers = value),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
    if (saved == true && mounted) {
      setState(() {
        _allowSuperResolution = allow;
        _rejectOutliers = outliers;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.processing.isAvailable) {
      return _buildUnavailable(context);
    }
    return _buildAvailable(context);
  }

  Widget _buildAvailable(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final savedCount = widget.session.savedCount;
    final canRun = savedCount > 0 && !_running;
    final progressValue = _total <= 0 ? null : (_completed / _total).clamp(0, 1).toDouble();
    final strategy = result?.strategy.isNotEmpty == true
        ? result!.strategy
        : 'Automatic. The engine chooses denoise, or 2× super-resolution when the shifts support it.';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reconstruction'),
        actions: [
          IconButton(
            tooltip: 'Advanced settings',
            onPressed: _running ? null : _showOptions,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.session.id, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(
            reconstructionStageLabel(_stage),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: crystalTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text('$savedCount input frames'),
          const SizedBox(height: 4),
          Text(strategy),
          if (_detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_detail),
          ],
          if (_running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              key: const ValueKey('reconstruction-progress'),
              value: progressValue,
            ),
          ],
          const SizedBox(height: 8),
          Text('Accepted $_accepted · Rejected $_rejected'),
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(result.message),
          ],
          const SizedBox(height: 16),
          if (_running)
            OutlinedButton(
              onPressed: () => _cancellation?.cancel(),
              child: const Text('Cancel'),
            )
          else
            FilledButton(
              onPressed: canRun ? _run : null,
              child: Text(
                savedCount == 0
                    ? 'No saved frames'
                    : result == null
                        ? 'Run reconstruction'
                        : 'Retry',
              ),
            ),
          const SizedBox(height: 16),
          Text('Pipeline', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final stage in _livePipeline)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _liveIcon(stage),
                color: _liveIcon(stage) == Icons.circle_outlined
                    ? theme.colorScheme.onSurface
                    : crystalTeal,
              ),
              title: Text(reconstructionStageLabel(stage)),
              subtitle: stage == ReconstructionStage.superResolving &&
                      result != null &&
                      result.success &&
                      !result.superResolutionPerformed
                  ? const Text('Skipped. The saved image is the native-resolution denoise.')
                  : null,
            ),
        ],
      ),
    );
  }

  IconData _liveIcon(ReconstructionStage stage) {
    final result = _result;
    if (_stage == ReconstructionStage.completed && result?.success == true) {
      if (stage == ReconstructionStage.superResolving && result?.superResolutionPerformed != true) {
        return Icons.remove_circle_outline;
      }
      return Icons.check_circle;
    }
    final current = _livePipeline.indexOf(_stage);
    final index = _livePipeline.indexOf(stage);
    if (current >= 0 && index >= 0 && index < current) {
      return Icons.check_circle;
    }
    return Icons.circle_outlined;
  }

  Widget _buildUnavailable(BuildContext context) {
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
            for (final stage in _unavailablePipeline)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _unavailableStageCompleted(stage) ? Icons.check_circle : Icons.circle_outlined,
                  color: _unavailableStageCompleted(stage)
                      ? crystalTeal
                      : theme.colorScheme.onSurface,
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
              value: result?.outputFilePath == null
                  ? 'Not available'
                  : 'Output file is ready to compare',
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

  bool _unavailableStageCompleted(ReconstructionStage stage) {
    if (_stage != ReconstructionStage.completed) {
      return false;
    }
    return _unavailablePipeline.contains(stage);
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
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
