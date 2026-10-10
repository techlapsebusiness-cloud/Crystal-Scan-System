import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'package:microscopeapp/core/storage/atomic_file.dart';
import 'package:microscopeapp/features/reconstruction/data/frame_fusion.dart';
import 'package:microscopeapp/features/reconstruction/data/frame_inspection.dart';
import 'package:microscopeapp/features/reconstruction/data/gray_plane.dart';
import 'package:microscopeapp/features/reconstruction/data/plane_transform.dart';
import 'package:microscopeapp/features/reconstruction/data/translational_registration.dart';
import 'package:microscopeapp/models/reconstruction_result.dart';

/// Local multi-frame reconstruction.
///
/// Registration is intensity search (translation, plus a small rotation).
/// Denoising is a weighted average that drops outlier pixels. Super-resolution
/// is shift-and-add with two iterative back-projection steps, and it runs only
/// when a frame has a measured subpixel shift and the 2× grid fits in the
/// pixel budget. opencv_dart is not used: this code runs in the Dart VM so
/// `flutter test` can execute it, and native OpenCV objects are not required.
class ReconstructionEngine {
  static const String version = '1';
  static const String denoiseAlgorithm = 'weighted-robust-average';
  static const String superResolutionAlgorithm = 'shift-and-add-ibp';

  Future<ReconstructionResult> run(
    ReconstructionRequest request, {
    void Function(ReconstructionProgress progress)? onProgress,
    ReconstructionCancellation? cancellation,
  }) async {
    final clock = Stopwatch()..start();
    final warnings = <String>[];
    final paths = request.originalImagePaths;
    final originalLengths = <String, int>{};
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        originalLengths[path] = await file.length();
      }
    }

    var accepted = 0;
    var rejected = 0;
    void emit(ReconstructionStage stage, int completed, int total, String detail) {
      onProgress?.call(
        ReconstructionProgress(
          stage: stage,
          completed: completed,
          total: total,
          framesAccepted: accepted,
          framesRejected: rejected,
          detail: detail,
        ),
      );
    }

    Future<ReconstructionResult> finish({
      required bool success,
      required ReconstructionStage stage,
      required String message,
      required String effectiveResolution,
      String algorithmName = denoiseAlgorithm,
      String strategy = '',
      bool superResolutionPerformed = false,
      double scaleFactor = 1,
      String? outputFilePath,
      String? denoisedFilePath,
      String? superResolutionFilePath,
      int? outputWidth,
      int? outputHeight,
      int? inputWidth,
      int? inputHeight,
      String? referenceFramePath,
      List<FrameReconstructionReport> frameReports = const [],
      Map<String, Object?> qualityMetrics = const {},
    }) async {
      final changed = await _changedOriginals(originalLengths);
      if (changed.isNotEmpty) {
        warnings.add('Original file length changed during processing: ${changed.join(', ')}');
      }
      String? metadataPath;
      final directoryReady = await _ensureResultsDirectory(request.outputDirectory);
      if (!directoryReady) {
        if (request.outputDirectory.isNotEmpty) {
          warnings.add(
            'Could not create the results folder. Storage may be full or the path is blocked.',
          );
        }
      }
      final result = ReconstructionResult(
        implemented: true,
        success: success,
        stage: stage,
        outputFilePath: outputFilePath,
        outputWidth: outputWidth,
        outputHeight: outputHeight,
        inputFrameCount: paths.length,
        framesAccepted: accepted,
        framesRejected: rejected,
        processingDuration: clock.elapsed,
        algorithmName: algorithmName,
        algorithmVersion: version,
        qualityMetrics: qualityMetrics,
        message: message,
        effectiveResolution: effectiveResolution,
        superResolutionPerformed: superResolutionPerformed,
        strategy: strategy,
        referenceFramePath: referenceFramePath,
        inputWidth: inputWidth,
        inputHeight: inputHeight,
        scaleFactor: scaleFactor,
        warnings: List<String>.unmodifiable(warnings),
        frameReports: frameReports,
        inputFramePaths: paths,
        denoisedFilePath: denoisedFilePath,
        superResolutionFilePath: superResolutionFilePath,
        metadataFilePath: directoryReady ? _metadataPath(request.outputDirectory) : null,
      );
      if (directoryReady) {
        try {
          await writeStringAtomic(
            File(_metadataPath(request.outputDirectory)),
            const JsonEncoder.withIndent('  ').convert(result.toJson()),
          );
          metadataPath = _metadataPath(request.outputDirectory);
        } on FileSystemException {
          warnings.add('The reconstruction metadata could not be saved.');
        }
      }
      emit(stage, stage == ReconstructionStage.completed ? 1 : 0, 1, message);
      if (metadataPath == null && result.metadataFilePath != null && warnings.isNotEmpty) {
        return ReconstructionResult(
          implemented: result.implemented,
          success: result.success,
          stage: result.stage,
          outputFilePath: result.outputFilePath,
          outputWidth: result.outputWidth,
          outputHeight: result.outputHeight,
          inputFrameCount: result.inputFrameCount,
          framesAccepted: result.framesAccepted,
          framesRejected: result.framesRejected,
          processingDuration: result.processingDuration,
          algorithmName: result.algorithmName,
          algorithmVersion: result.algorithmVersion,
          qualityMetrics: result.qualityMetrics,
          message: result.message,
          effectiveResolution: result.effectiveResolution,
          superResolutionPerformed: result.superResolutionPerformed,
          strategy: result.strategy,
          referenceFramePath: result.referenceFramePath,
          inputWidth: result.inputWidth,
          inputHeight: result.inputHeight,
          scaleFactor: result.scaleFactor,
          warnings: List<String>.unmodifiable(warnings),
          frameReports: result.frameReports,
          inputFramePaths: result.inputFramePaths,
          denoisedFilePath: result.denoisedFilePath,
          superResolutionFilePath: result.superResolutionFilePath,
        );
      }
      return result;
    }

    bool cancelled() => cancellation?.isCancelled ?? false;

    if (cancelled()) {
      return finish(
        success: false,
        stage: ReconstructionStage.cancelled,
        message: 'Reconstruction was cancelled. Original frames were not modified.',
        effectiveResolution: _notValidated,
      );
    }
    if (paths.isEmpty) {
      return finish(
        success: false,
        stage: ReconstructionStage.failed,
        message: 'This session has no frames. Capture a sequence before reconstruction.',
        effectiveResolution: _notValidated,
      );
    }

    emit(ReconstructionStage.preparing, 0, paths.length, 'Checking ${paths.length} frames.');
    final work = <_FrameWork>[];
    for (var index = 0; index < paths.length; index++) {
      if (cancelled()) {
        return finish(
          success: false,
          stage: ReconstructionStage.cancelled,
          message: 'Reconstruction was cancelled. Original frames were not modified.',
          effectiveResolution: _notValidated,
          frameReports: [for (final frame in work) frame.report()],
        );
      }
      emit(
        ReconstructionStage.analyzing,
        index,
        paths.length,
        'Measuring frame ${index + 1} of ${paths.length}.',
      );
      final inspection = await inspectFrame(paths[index]);
      final frame = _FrameWork(inspection);
      if (inspection.rejectionReason != null) {
        frame.rejection = inspection.rejectionReason;
        rejected++;
      }
      work.add(frame);
      emit(
        ReconstructionStage.analyzing,
        index + 1,
        paths.length,
        'Measured frame ${index + 1} of ${paths.length}.',
      );
    }

    final geometry = _dominantSize(work);
    if (geometry != null) {
      for (final frame in work) {
        if (frame.rejection != null || !frame.inspection.decoded) {
          continue;
        }
        if (frame.inspection.imageWidth != geometry.width ||
            frame.inspection.imageHeight != geometry.height) {
          frame.rejection =
              'The image is ${frame.inspection.imageWidth}×${frame.inspection.imageHeight}, which does not match the other frames. It was not stretched.';
          rejected++;
        }
      }
    }

    for (final frame in work) {
      if (frame.rejection != null) {
        continue;
      }
      final highlights = frame.inspection.highlightClip ?? 0;
      final shadows = frame.inspection.shadowClip ?? 0;
      final mean = frame.inspection.meanLuminance ?? 0;
      if (highlights > 0.60 && mean > 0.85) {
        frame.rejection = 'The frame is heavily overexposed.';
        rejected++;
      } else if (shadows > 0.60 && mean < 0.10) {
        frame.rejection = 'The frame is heavily underexposed.';
        rejected++;
      }
    }

    final sharpnessValues = <double>[
      for (final frame in work)
        if (frame.rejection == null) frame.inspection.sharpness ?? 0,
    ]..sort();
    final sharpest = sharpnessValues.isEmpty ? 0.0 : sharpnessValues[sharpnessValues.length ~/ 2];
    if (sharpest > 0.01) {
      for (final frame in work) {
        if (frame.rejection != null) {
          continue;
        }
        final sharpness = frame.inspection.sharpness ?? 0;
        if (sharpness < sharpest * 0.2 && sharpness < 0.008) {
          frame.rejection =
              'The frame is much softer than the sharpest frame in the session, so it was excluded as blurred.';
          rejected++;
        }
      }
    }

    final usable = [for (final frame in work) if (frame.rejection == null) frame];
    emit(ReconstructionStage.selectingReference, 0, 1, 'Choosing a reference frame.');
    if (usable.isEmpty) {
      accepted = 0;
      rejected = work.length;
      return finish(
        success: false,
        stage: ReconstructionStage.failed,
        message:
            'No frame was usable. Recapture the subject with more even light and a steady camera. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
      );
    }
    usable.sort((a, b) => b.score.compareTo(a.score));
    final selection = await _selectReference(
      usable: usable,
      cancelled: cancelled,
      emit: emit,
      onCancel: () => finish(
        success: false,
        stage: ReconstructionStage.cancelled,
        message: 'Reconstruction was cancelled. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
      ),
    );
    if (selection.cancelledResult != null) {
      return selection.cancelledResult!;
    }
    final reference = selection.reference;
    final referenceImage = selection.image;
    if (reference == null) {
      return finish(
        success: false,
        stage: ReconstructionStage.failed,
        message: 'The reference frame could not be read a second time.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
      );
    }
    for (final frame in usable) {
      if (identical(frame, reference)) {
        continue;
      }
      final estimate = selection.estimates[frame];
      frame.registration = estimate;
      if (estimate == null || !estimate.accepted) {
        frame.rejection = estimate?.rejectionReason ?? 'The frame could not be read for alignment.';
      }
    }

    final aligned = [
      for (final frame in usable)
        if (frame.reference || frame.registration?.accepted == true) frame,
    ];
    accepted = aligned.length;
    rejected = work.length - accepted;
    emit(
      ReconstructionStage.rejecting,
      accepted,
      work.length,
      '$accepted frames accepted, $rejected rejected.',
    );

    if (aligned.length < 2 || referenceImage == null) {
      return finish(
        success: false,
        stage: ReconstructionStage.failed,
        message: aligned.isEmpty
            ? 'No frame was usable. Recapture the subject. Original frames were not modified.'
            : 'Only ${aligned.length} frame was usable. At least two are required, so nothing was combined. Recapture with the phone held still. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
        referenceFramePath: reference.inspection.path,
        inputWidth: reference.inspection.imageWidth,
        inputHeight: reference.inspection.imageHeight,
      );
    }

    if (cancelled()) {
      return finish(
        success: false,
        stage: ReconstructionStage.cancelled,
        message: 'Reconstruction was cancelled. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
        referenceFramePath: reference.inspection.path,
      );
    }

    final fusionFrames = [
      for (final frame in aligned)
        FusionFrame(
          path: frame.inspection.path,
          transform: frame.registration?.transform ?? const PlaneTransform(),
          registrationMae: frame.registration?.mae ?? 0,
        ),
    ];
    emit(ReconstructionStage.denoising, 0, fusionFrames.length, 'Combining ${fusionFrames.length} frames.');
    final denoised = await denoiseFrames(
      reference: referenceImage,
      referencePath: reference.inspection.path,
      frames: fusionFrames,
      rejectOutliers: request.options.rejectOutliers,
      isCancelled: cancelled,
      onFrame: (completed, total) {
        emit(ReconstructionStage.denoising, completed, total, 'Denoising frame $completed of $total.');
      },
    );
    if (cancelled()) {
      return finish(
        success: false,
        stage: ReconstructionStage.cancelled,
        message: 'Reconstruction was cancelled. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
        referenceFramePath: reference.inspection.path,
      );
    }
    if (denoised.image == null) {
      return finish(
        success: false,
        stage: ReconstructionStage.failed,
        message: denoised.failure ?? 'Denoising did not produce an image. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
        referenceFramePath: reference.inspection.path,
        inputWidth: referenceImage.width,
        inputHeight: referenceImage.height,
      );
    }

    final skipReason = _superResolutionSkipReason(
      aligned: aligned,
      width: referenceImage.width,
      height: referenceImage.height,
      options: request.options,
    );
    img.Image? superImage;
    double? reprojection;
    if (skipReason != null) {
      warnings.add(skipReason);
    } else {
      emit(
        ReconstructionStage.superResolving,
        0,
        fusionFrames.length + 2,
        'Building a 2× estimate from subpixel shifts.',
      );
      final solved = await superResolveFrames(
        reference: referenceImage,
        referencePath: reference.inspection.path,
        denoised: denoised.image!,
        frames: fusionFrames,
        rejectOutliers: request.options.rejectOutliers,
        isCancelled: cancelled,
        onFrame: (completed, total) {
          emit(
            ReconstructionStage.superResolving,
            completed,
            total,
            'Super-resolution step $completed of $total.',
          );
        },
      );
      if (cancelled()) {
        return finish(
          success: false,
          stage: ReconstructionStage.cancelled,
          message: 'Reconstruction was cancelled. Original frames were not modified.',
          effectiveResolution: _notValidated,
          frameReports: [for (final frame in work) frame.report()],
          referenceFramePath: reference.inspection.path,
        );
      }
      if (solved == null) {
        warnings.add(
          'Super-resolution did not cover enough of the high-resolution grid, so the saved result is the native-resolution denoise.',
        );
      } else {
        superImage = solved.image;
        reprojection = solved.reprojectionError;
      }
    }

    if (!await _ensureResultsDirectory(request.outputDirectory)) {
      return finish(
        success: false,
        stage: ReconstructionStage.failed,
        message:
            'Could not create the results folder. Storage may be full or the path is blocked. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
        referenceFramePath: reference.inspection.path,
        inputWidth: referenceImage.width,
        inputHeight: referenceImage.height,
      );
    }

    emit(ReconstructionStage.saving, 0, superImage == null ? 1 : 2, 'Saving the reconstruction.');
    final denoisedPath = '${request.outputDirectory}/denoised.png';
    final superPath = '${request.outputDirectory}/super_resolution.png';
    try {
      await writeBytesAtomic(File(denoisedPath), img.encodePng(denoised.image!));
    } on FileSystemException {
      return finish(
        success: false,
        stage: ReconstructionStage.failed,
        message: 'The denoised image could not be saved. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
        referenceFramePath: reference.inspection.path,
        inputWidth: referenceImage.width,
        inputHeight: referenceImage.height,
      );
    }
    if (!await _pngMatches(denoisedPath, denoised.image!.width, denoised.image!.height)) {
      await _deleteIfPresent(denoisedPath);
      return finish(
        success: false,
        stage: ReconstructionStage.failed,
        message: 'The denoised image failed validation and was discarded. Original frames were not modified.',
        effectiveResolution: _notValidated,
        frameReports: [for (final frame in work) frame.report()],
        referenceFramePath: reference.inspection.path,
        inputWidth: referenceImage.width,
        inputHeight: referenceImage.height,
      );
    }

    var superResolutionPerformed = false;
    if (superImage != null) {
      try {
        await writeBytesAtomic(File(superPath), img.encodePng(superImage));
        if (await _pngMatches(superPath, superImage.width, superImage.height)) {
          superResolutionPerformed = true;
        } else {
          await _deleteIfPresent(superPath);
          warnings.add('The super-resolution file failed validation and was discarded.');
        }
      } on FileSystemException {
        await _deleteIfPresent(superPath);
        warnings.add('The super-resolution file could not be saved. The denoised image was kept.');
      }
    } else {
      await _deleteIfPresent(superPath);
    }
    emit(ReconstructionStage.saving, 1, 1, 'Saved.');

    final noiseReference = _round(highFrequencyMad(referenceImage));
    final noiseOutput = _round(highFrequencyMad(superResolutionPerformed ? superImage! : denoised.image!));
    final registrationValues = [
      for (final frame in aligned)
        if (!frame.reference && frame.registration != null) frame.registration!.mae,
    ];
    final overlapValues = [
      for (final frame in aligned)
        if (!frame.reference && frame.registration != null) frame.registration!.overlap,
    ];
    final meanMae = registrationValues.isEmpty
        ? 0.0
        : registrationValues.reduce((a, b) => a + b) / registrationValues.length;
    final meanOverlap = overlapValues.isEmpty
        ? 1.0
        : overlapValues.reduce((a, b) => a + b) / overlapValues.length;
    final difference = meanAbsoluteDifference(denoised.image!, referenceImage);

    final metrics = <String, Object?>{
      'highFrequencyMadReference': noiseReference,
      'highFrequencyMadOutput': noiseOutput,
      'meanRegistrationMae': _round(meanMae),
      'meanOverlap': _round(meanOverlap),
      'meanAbsoluteDifferenceFromReference': _round(difference),
      if (reprojection != null && superResolutionPerformed)
        'reprojectionMeanAbsoluteError': _round(reprojection),
    };

    final output = superResolutionPerformed ? superImage! : denoised.image!;
    final sharpnesses = [
      for (final frame in aligned)
        if (frame.inspection.sharpness != null) frame.inspection.sharpness!,
    ];
    if (sharpnesses.length >= 2) {
      final high = sharpnesses.reduce(math.max);
      final low = sharpnesses.reduce(math.min);
      if (low > 0 && high / low > 3) {
        warnings.add(
          'Sharpness differs across the accepted frames. Focus stacking was not performed.',
        );
      }
    }
    if (aligned.any((frame) => frame.registration?.lowTexture == true)) {
      warnings.add(
        'At least one accepted frame has very little texture. Alignment fell back to the identity shift, and super-resolution was not attempted from that evidence.',
      );
    }

    final strategy = superResolutionPerformed ? 'multi-frame-super-resolution' : 'multi-frame-denoise';
    final algorithm = superResolutionPerformed ? superResolutionAlgorithm : denoiseAlgorithm;
    final scale = superResolutionPerformed ? 2.0 : 1.0;
    final message = StringBuffer()
      ..write(
        'Combined $accepted of ${paths.length} frames. ',
      )
      ..write(
        superResolutionPerformed
            ? 'Super-resolution used a 2× sampling grid (${output.width}×${output.height} pixels) from measured subpixel shifts. '
            : 'The saved image is a native-resolution denoise (${output.width}×${output.height} pixels). Super-resolution was not performed. ',
      )
      ..write(
        'High-frequency MAD was $noiseReference on the reference and $noiseOutput on the output. ',
      )
      ..write(
        'Mean registration error was ${_round(meanMae).toStringAsFixed(4)} and mean overlap was ${_round(meanOverlap).toStringAsFixed(3)}. ',
      )
      ..write('Effective optical resolution was not independently validated.');
    if (skipReason != null && !superResolutionPerformed) {
      message.write(' $skipReason');
    }

    return finish(
      success: true,
      stage: ReconstructionStage.completed,
      message: message.toString(),
      effectiveResolution: superResolutionPerformed
          ? 'Output file is ${output.width}×${output.height} pixels (2× the input sampling grid). Pixel count is not a measurement of effective optical resolution, which was not independently validated.'
          : 'Output file is ${output.width}×${output.height} pixels at the input sampling grid. Super-resolution was not performed. Effective optical resolution was not independently validated.',
      algorithmName: algorithm,
      strategy: strategy,
      superResolutionPerformed: superResolutionPerformed,
      scaleFactor: scale,
      outputFilePath: superResolutionPerformed ? superPath : denoisedPath,
      denoisedFilePath: denoisedPath,
      superResolutionFilePath: superResolutionPerformed ? superPath : null,
      outputWidth: output.width,
      outputHeight: output.height,
      inputWidth: referenceImage.width,
      inputHeight: referenceImage.height,
      referenceFramePath: reference.inspection.path,
      frameReports: [for (final frame in work) frame.report()],
      qualityMetrics: metrics,
    );
  }
}

class _ReferenceSelection {
  const _ReferenceSelection({
    this.reference,
    this.image,
    this.estimates = const {},
    this.cancelledResult,
  });

  final _FrameWork? reference;
  final img.Image? image;
  final Map<_FrameWork, RegistrationEstimate> estimates;
  final ReconstructionResult? cancelledResult;
}

Future<_ReferenceSelection> _selectReference({
  required List<_FrameWork> usable,
  required bool Function() cancelled,
  required void Function(ReconstructionStage stage, int completed, int total, String detail) emit,
  required Future<ReconstructionResult> Function() onCancel,
}) async {
  if (usable.length == 1) {
    final only = usable.first;
    only.reference = true;
    only.registration = _identityEstimate(only);
    emit(ReconstructionStage.selectingReference, 1, 1, 'Reference is ${only.inspection.path}.');
    return _ReferenceSelection(reference: only);
  }

  final limit = math.min(3, usable.length);
  _FrameWork? bestFrame;
  img.Image? bestImage;
  var bestEstimates = <_FrameWork, RegistrationEstimate>{};
  var bestCount = -1;

  for (var candidateIndex = 0; candidateIndex < limit; candidateIndex++) {
    final candidate = usable[candidateIndex];
    emit(
      ReconstructionStage.selectingReference,
      candidateIndex,
      limit,
      'Checking reference ${candidateIndex + 1} of $limit.',
    );
    final image = await decodeOriented(candidate.inspection.path);
    if (image == null) {
      continue;
    }
    final gray = GrayPlane.fromImage(image);
    final estimates = <_FrameWork, RegistrationEstimate>{};
    final others = [for (final frame in usable) if (!identical(frame, candidate)) frame];
    var count = 0;
    for (var index = 0; index < others.length; index++) {
      if (cancelled()) {
        return _ReferenceSelection(cancelledResult: await onCancel());
      }
      emit(
        ReconstructionStage.estimatingMotion,
        index,
        others.length,
        'Estimating motion for frame ${index + 1} of ${others.length}.',
      );
      final moving = await decodeOriented(others[index].inspection.path);
      if (moving == null) {
        estimates[others[index]] = RegistrationEstimate.rejected('The frame could not be read for alignment.');
      } else if (moving.width != image.width || moving.height != image.height) {
        estimates[others[index]] = RegistrationEstimate.rejected(
          'The frame size does not match the reference, so it was not stretched to fit.',
        );
      } else {
        final estimate = estimateTranslation(gray, GrayPlane.fromImage(moving));
        estimates[others[index]] = estimate;
        if (estimate.accepted) {
          count++;
        }
      }
      emit(
        ReconstructionStage.aligning,
        index + 1,
        others.length,
        'Aligned frame ${index + 1} of ${others.length}.',
      );
    }
    if (count > bestCount) {
      bestCount = count;
      bestFrame = candidate;
      bestImage = image;
      bestEstimates = estimates;
    }
    if (count == others.length) {
      break;
    }
  }

  final chosen = bestFrame;
  final chosenImage = bestImage;
  if (chosen == null || chosenImage == null) {
    return const _ReferenceSelection();
  }
  chosen.reference = true;
  chosen.registration = _identityEstimate(chosen);
  emit(ReconstructionStage.selectingReference, 1, 1, 'Reference is ${chosen.inspection.path}.');
  return _ReferenceSelection(reference: chosen, image: chosenImage, estimates: bestEstimates);
}

RegistrationEstimate _identityEstimate(_FrameWork frame) {
  return RegistrationEstimate(
    transform: const PlaneTransform(),
    mae: 0,
    overlap: 1,
    accepted: true,
    periodicAmbiguity: false,
    lowTexture: (frame.inspection.texture ?? 0) < 0.02,
    confidence: 1,
  );
}

const String _notValidated =
    'Not measured. No reconstruction file was saved, and effective optical resolution was not independently validated.';

class _Size {
  const _Size(this.width, this.height);
  final int width;
  final int height;
}

class _FrameWork {
  _FrameWork(this.inspection);

  final FrameInspection inspection;
  String? rejection;
  RegistrationEstimate? registration;
  bool reference = false;

  double get score {
    final sharpness = inspection.sharpness ?? 0;
    final texture = inspection.texture ?? 0;
    final highlights = inspection.highlightClip ?? 0;
    final shadows = inspection.shadowClip ?? 0;
    return sharpness * (0.15 + texture) * (1 - highlights) * (1 - shadows);
  }

  bool get accepted => reference || (rejection == null && registration?.accepted == true);

  FrameReconstructionReport report() {
    final shift = registration?.transform;
    return FrameReconstructionReport(
      path: inspection.path,
      accepted: accepted && rejection == null,
      rejectionReason: rejection,
      width: inspection.imageWidth,
      height: inspection.imageHeight,
      fileSizeBytes: inspection.fileSizeBytes,
      sharpness: inspection.sharpness,
      meanLuminance: inspection.meanLuminance,
      highlightClip: inspection.highlightClip,
      shadowClip: inspection.shadowClip,
      texture: inspection.texture,
      dx: shift?.dx,
      dy: shift?.dy,
      angleDegrees: shift?.angleDegrees,
      registrationMae: registration?.mae,
      overlap: registration?.overlap,
      periodicAmbiguity: registration?.periodicAmbiguity ?? false,
      lowTexture: registration?.lowTexture ?? false,
      reference: reference,
    );
  }
}

_Size? _dominantSize(List<_FrameWork> frames) {
  final counts = <String, int>{};
  final sizes = <String, _Size>{};
  for (final frame in frames) {
    if (!frame.inspection.decoded || frame.rejection != null) {
      continue;
    }
    final key = '${frame.inspection.imageWidth}x${frame.inspection.imageHeight}';
    counts[key] = (counts[key] ?? 0) + 1;
    sizes[key] = _Size(frame.inspection.imageWidth!, frame.inspection.imageHeight!);
  }
  if (counts.isEmpty) {
    return null;
  }
  String? bestKey;
  for (final entry in counts.entries) {
    if (bestKey == null) {
      bestKey = entry.key;
      continue;
    }
    final bestCount = counts[bestKey]!;
    final bestArea = sizes[bestKey]!.width * sizes[bestKey]!.height;
    final area = sizes[entry.key]!.width * sizes[entry.key]!.height;
    if (entry.value > bestCount || (entry.value == bestCount && area > bestArea)) {
      bestKey = entry.key;
    }
  }
  return sizes[bestKey];
}

String? _superResolutionSkipReason({
  required List<_FrameWork> aligned,
  required int width,
  required int height,
  required ReconstructionOptions options,
}) {
  if (!options.allowSuperResolution) {
    return 'Super-resolution is turned off in advanced settings.';
  }
  final pixels = width * height * 4;
  if (pixels > options.maxSuperResolutionPixels) {
    return 'A 2× reconstruction would be ${width * 2}×${height * 2} pixels, above the working limit of ${options.maxSuperResolutionPixels} output pixels. The saved result is the native-resolution denoise.';
  }
  if (aligned.any((frame) => frame.registration?.lowTexture == true)) {
    return 'The frames do not contain enough texture to support a subpixel shift estimate. Super-resolution was not performed.';
  }
  if (aligned.any((frame) => frame.registration?.periodicAmbiguity == true)) {
    return 'Repetitive texture made another shift almost as likely, so super-resolution was not performed.';
  }
  if (aligned.any((frame) => (frame.registration?.transform.angleDegrees ?? 0).abs() > 0.35)) {
    return 'A frame needed a rotation. Super-resolution here uses translation only, so it was not performed.';
  }
  final useful = aligned.any((frame) {
    final shift = frame.registration?.transform;
    if (shift == null || frame.reference) {
      return false;
    }
    return _fractional(shift.dx) >= 0.12 || _fractional(shift.dy) >= 0.12;
  });
  if (!useful) {
    return 'The measured shifts are whole pixels, so there is no complementary subpixel sample to reconstruct. Spatial resolution was not increased.';
  }
  return null;
}

double _fractional(double value) => (value - value.round()).abs();

double _round(double value) {
  if (value.isNaN || value.isInfinite) {
    return 0;
  }
  return double.parse(value.toStringAsFixed(6));
}

Future<List<String>> _changedOriginals(Map<String, int> lengths) async {
  final changed = <String>[];
  for (final entry in lengths.entries) {
    final file = File(entry.key);
    if (!await file.exists() || await file.length() != entry.value) {
      changed.add(entry.key);
    }
  }
  return changed;
}

Future<bool> _ensureResultsDirectory(String path) async {
  if (path.isEmpty) {
    return false;
  }
  if (await File(path).exists()) {
    return false;
  }
  try {
    await Directory(path).create(recursive: true);
  } on FileSystemException {
    return false;
  }
  return true;
}

String _metadataPath(String directory) => '$directory/reconstruction.json';

Future<bool> _pngMatches(String path, int width, int height) async {
  final file = File(path);
  if (!await file.exists() || await file.length() <= 0) {
    return false;
  }
  final decoded = img.decodePng(await file.readAsBytes());
  return decoded != null && decoded.width == width && decoded.height == height;
}

Future<void> _deleteIfPresent(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
