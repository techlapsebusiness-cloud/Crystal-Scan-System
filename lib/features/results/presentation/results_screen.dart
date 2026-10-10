import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/core/utils/formatters.dart';
import 'package:microscopeapp/models/reconstruction_result.dart';

enum _ResultView { original, reconstructed, compare }

/// Shows the reference frame beside the reconstruction and can export it.
///
/// Images are drawn from the files on disk with no cache-width downsample, so
/// a zoom inspects the saved pixels.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    required this.sessionId,
    required this.result,
  });

  final String sessionId;
  final ReconstructionResult result;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final TransformationController _transform = TransformationController();
  _ResultView _view = _ResultView.compare;
  double _split = 0.5;
  String? _shownPath;
  var _exporting = false;

  @override
  void initState() {
    super.initState();
    _shownPath = widget.result.outputFilePath;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final theme = Theme.of(context);
    final referencePath = result.referenceFramePath;
    final reconstructedPath = _shownPath;
    final hasDenoised = result.denoisedFilePath != null;
    final hasSuper = result.superResolutionFilePath != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        actions: [
          IconButton(
            tooltip: 'Fit to screen',
            onPressed: () => _transform.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.sessionId, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(
                  result.superResolutionPerformed
                      ? 'Multi-frame super-resolution on a 2× sampling grid. This is not an optical-resolution measurement.'
                      : 'Native-resolution denoised reconstruction. Super-resolution was not performed.',
                  style: theme.textTheme.titleSmall?.copyWith(color: crystalTeal),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<_ResultView>(
              segments: const [
                ButtonSegment(value: _ResultView.original, label: Text('Original')),
                ButtonSegment(value: _ResultView.reconstructed, label: Text('Result')),
                ButtonSegment(value: _ResultView.compare, label: Text('Compare')),
              ],
              selected: {_view},
              onSelectionChanged: (selection) => setState(() => _view = selection.first),
            ),
          ),
          if (hasDenoised && hasSuper)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'denoise', label: Text('Denoised')),
                  ButtonSegment(value: 'super', label: Text('Super-resolved')),
                ],
                selected: {
                  reconstructedPath == result.superResolutionFilePath ? 'super' : 'denoise',
                },
                onSelectionChanged: (selection) {
                  setState(() {
                    _shownPath = selection.first == 'super'
                        ? result.superResolutionFilePath
                        : result.denoisedFilePath;
                    _transform.value = Matrix4.identity();
                  });
                },
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: crystalSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: 0.8,
                    maxScale: 12,
                    child: _view == _ResultView.compare
                        ? _CompareView(
                            originalPath: referencePath,
                            reconstructedPath: reconstructedPath,
                            split: _split,
                          )
                        : _StillView(
                            path: _view == _ResultView.original ? referencePath : reconstructedPath,
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (_view == _ResultView.compare)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text('Result'),
                  ),
                  Expanded(
                    child: Slider(
                      value: _split,
                      onChanged: (value) => setState(() => _split = value),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text('Original'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _exporting || reconstructedPath == null
                        ? null
                        : () => _exportTiff(reconstructedPath),
                    child: const Text('Export TIFF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: reconstructedPath == null ? null : () => _share(reconstructedPath),
                    child: const Text('Share'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _Fact(
                  label: 'Input dimensions',
                  value: result.inputWidth == null || result.inputHeight == null
                      ? 'Not available'
                      : '${result.inputWidth}×${result.inputHeight} pixels',
                ),
                _Fact(
                  label: 'Output dimensions',
                  value: result.outputWidth == null || result.outputHeight == null
                      ? 'Not available'
                      : '${result.outputWidth}×${result.outputHeight} pixels',
                ),
                _Fact(
                  label: 'Upscaling factor',
                  value: result.superResolutionPerformed
                      ? '${result.scaleFactor.toStringAsFixed(0)}× linear, from measured shifts'
                      : '1×. The output uses the input sampling grid.',
                ),
                _Fact(
                  label: 'Frames',
                  value:
                      '${result.inputFrameCount} captured, ${result.framesAccepted} used, ${result.framesRejected} rejected',
                ),
                _Fact(label: 'Algorithm', value: '${result.algorithmName} ${result.algorithmVersion}'),
                _Fact(label: 'Strategy', value: result.strategy.isEmpty ? 'Not recorded' : result.strategy),
                _Fact(label: 'Duration', value: _durationLabel(result.processingDuration)),
                _Fact(
                  label: 'Registration',
                  value: _metricLine(result, 'meanRegistrationMae', 'mean overlap', 'meanOverlap'),
                ),
                _Fact(
                  label: 'High-frequency MAD',
                  value:
                      'Reference ${_metric(result, 'highFrequencyMadReference')}, output ${_metric(result, 'highFrequencyMadOutput')}',
                ),
                if (result.qualityMetrics['reprojectionMeanAbsoluteError'] != null)
                  _Fact(
                    label: 'Reprojection error',
                    value:
                        '${_metric(result, 'reprojectionMeanAbsoluteError')} mean absolute error, 0–255',
                  ),
                _Fact(
                  label: 'Effective resolution',
                  value: result.effectiveResolution ?? ReconstructionResult.notMeasuredResolution,
                ),
                if (result.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Warnings', style: theme.textTheme.titleSmall),
                  for (final warning in result.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(warning),
                    ),
                ],
                if (result.frameReports.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Frames', style: theme.textTheme.titleSmall),
                  for (final report in result.frameReports)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        report.accepted ? Icons.check_circle : Icons.cancel,
                        color: report.accepted ? crystalTeal : crystalDanger,
                      ),
                      title: Text(_fileName(report.path)),
                      subtitle: Text(_frameSubtitle(report)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _frameSubtitle(FrameReconstructionReport report) {
    if (!report.accepted) {
      return report.rejectionReason ?? 'Rejected';
    }
    final dx = report.dx?.toStringAsFixed(2) ?? '0';
    final dy = report.dy?.toStringAsFixed(2) ?? '0';
    final mae = report.registrationMae?.toStringAsFixed(4) ?? '—';
    final overlap = report.overlap?.toStringAsFixed(3) ?? '—';
    final role = report.reference ? 'Reference. ' : '';
    return '${role}Shift ($dx, $dy), error $mae, overlap $overlap';
  }

  Future<void> _exportTiff(String pngPath) async {
    setState(() => _exporting = true);
    try {
      final bytes = await File(pngPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _tell('The reconstruction file could not be read for TIFF export.');
        return;
      }
      final tiffPath = pngPath.replaceAll(RegExp(r'\.png$'), '.tiff');
      final target = tiffPath == pngPath ? '$pngPath.tiff' : tiffPath;
      await File(target).writeAsBytes(img.encodeTiff(decoded), flush: true);
      _tell('TIFF saved at $target');
    } catch (error) {
      _tell('TIFF export failed. $error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _share(String path) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'image/png')],
          title: 'Crystal Scan reconstruction',
          text: widget.result.superResolutionPerformed
              ? 'Crystal Scan 2× super-resolution'
              : 'Crystal Scan denoised reconstruction',
        ),
      );
    } catch (error) {
      _tell('Sharing is not available on this device. The file is saved at $path');
    }
  }

  void _tell(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CompareView extends StatelessWidget {
  const _CompareView({
    required this.originalPath,
    required this.reconstructedPath,
    required this.split,
  });

  final String? originalPath;
  final String? reconstructedPath;
  final double split;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _StillView(path: originalPath),
        ClipRect(
          clipper: _SplitClipper(split),
          child: _StillView(path: reconstructedPath),
        ),
      ],
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  const _SplitClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_SplitClipper oldClipper) => oldClipper.fraction != fraction;
}

class _StillView extends StatelessWidget {
  const _StillView({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final filePath = path;
    if (filePath == null || !File(filePath).existsSync()) {
      return const Center(child: Text('Image file is not available.'));
    }
    return Image.file(
      File(filePath),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      errorBuilder: (context, error, stackTrace) {
        return const Center(child: Text('This image could not be displayed.'));
      },
    );
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

String _fileName(String path) {
  final slash = path.lastIndexOf('/');
  return slash == -1 ? path : path.substring(slash + 1);
}

String _durationLabel(Duration duration) {
  if (duration.inSeconds < 1) {
    return '${duration.inMilliseconds} ms';
  }
  return formatDuration(duration);
}

String _metric(ReconstructionResult result, String key) {
  final value = result.qualityMetrics[key];
  if (value is num) {
    return value.toStringAsFixed(4);
  }
  return 'not measured';
}

String _metricLine(ReconstructionResult result, String errorKey, String overlapLabel, String overlapKey) {
  return 'Mean absolute error ${_metric(result, errorKey)} (0–1), $overlapLabel ${_metric(result, overlapKey)}';
}
