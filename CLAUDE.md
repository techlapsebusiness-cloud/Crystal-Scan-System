# Crystal Scan

Flutter app (package `microscopeapp`, display name **Crystal Scan**). It captures a burst of stills of a stationary subject on a phone and reconstructs a cleaner image on the device. When the frames contain a useful subpixel shift and the output fits a pixel budget, it also runs a separate 2× multi-frame super-resolution. The user never classifies the subject. Circuits, plants, documents, fabric, and ordinary photographs use the same pipeline.

Flutter 3.41.7, Dart 3.11.5. Android-first. `minSdk` is `max(flutter.minSdk, 24)`. No backend, no cloud upload, no extra state-management package. Dependencies are wired with `AppScope` (`InheritedWidget`).

## Product rules

These are constraints, not suggestions.

- Preserve the existing capture flow. Do not rebuild the app or add a second capture implementation.
- Do not add a subject-specific or PCB-specific model. Do not assume straight edges, particular colors, solder shapes, or a fixed texture.
- Do not treat resizing, sharpening, contrast, denoising, or focus stacking as super-resolution.
- Do not write `super_resolution.png` unless 2× reconstruction actually ran. Do not claim 12K, and do not claim that more frames raise resolution.
- Do not invent quality percentages. Report measured values (dimensions, frame counts, registration MAE, overlap, high-frequency MAD, PSNR only when a synthetic ground truth exists). Effective optical resolution is **not independently validated**.
- Never overwrite or delete original frames. If processing fails or is cancelled, leave the JPEGs as they were and do not keep a partial output image.
- Do not silently stretch frames to a common size. Do not accept an alignment just because a function returned.
- Keep processing on the device. Do not add a required network call.
- `opencv_dart` is not a dependency. The engine is pure Dart on `package:image` so `flutter test` runs without a native OpenCV build. Do not invent OpenCV API names. Feature matching, ECC, and homography are not implemented.

## What the app does

1. Rear-camera preview with a framing guide.
2. Capture 16, 32, 64, or 128 frames, one shutter press per frame.
3. Lock focus, exposure, flash, zoom, and lens for the session when the camera allows it. Autofocus and auto exposure run once before the first frame, not between frames. ISO, shutter, focus distance, and exposure compensation are not recorded; the camera plugin does not expose them without changing the image.
4. Save originals under app documents and write `session.json` atomically after each frame.
5. Session list, summary, thumbnails, and a single-frame viewer.
6. Local reconstruction: load, quality, reference selection, registration, rejection, robust denoise, optional 2× super-resolution, atomic PNG plus `reconstruction.json`.
7. Results screen: original, reconstruction, split compare, zoom and pan, fit, TIFF export, share.

A tripod keeps the phone still. It does not create the subpixel shifts a resolution increase needs.

## Navigation

`main.dart` opens `SessionStore`, marks interrupted sessions, and starts `CrystalScanApp` with `ImageProcessingService.local()`.

- `CaptureScreen` is home.
- After a capture, it pushes `SessionSummaryScreen`.
- The summary can open `FrameViewerScreen`, pop back to capture, or push `ReconstructionScreen` (**Continue to reconstruction**).
- `SessionListScreen` opens a saved session's summary.
- When reconstruction succeeds and the output file exists and is non-empty, `ReconstructionScreen` pushes `ResultsScreen`.

`ImageProcessingService.unavailable()` still exists. Tests use it. The unavailable screen must stay honest: stage label **Not implemented**, message contains “not implemented”, effective resolution contains “Not measured”, no output file, no `LinearProgressIndicator`, no `Icons.check_circle`. The button label is **Run reconstruction**. Do not change the preparing-stage label away from **Preparing images**.

## Storage

Root: application documents directory plus `crystal_scan/sessions`.

```text
crystal_scan/sessions/<session_id>/
  session.json
  frames/frame_0001.jpg
  results/denoised.png
  results/super_resolution.png    # only when 2× reconstruction ran
  results/reconstruction.json
```

- Session id: `^session_\d{8}_\d{6}_\d{3}_[0-9a-f]{4}$` (`SessionIds`).
- Frame names: `frame_NNNN.jpg`, 4 digits, 1-based (`frameFileName`).
- Capture progress percent is based on **saved** frames, never 100 before the last successful save.
- `session.json` and result bytes go through `writeStringAtomic` / `writeBytesAtomic` (temp sibling, then rename).
- The live engine writes to `<session>/results`. The unavailable UI path passes `<session>/output` and writes nothing.
- On launch, `markInterruptedSessions()` marks a session that was still capturing when the process died. Saved frames are kept.

## Capture

Implementation: `lib/features/capture/data/capture_service.dart` (re-exported from `lib/services/capture_service.dart`).

- Allowed counts: `allowedFrameCounts` = 16, 32, 64, 128. Anything else throws.
- One session at a time. A second call throws `CaptureBusyException`.
- Camera must be ready. `prepareStableCapture()` runs once, then frames are taken in order.
- `interFrameDelay` defaults to 100 ms. That is a pipeline settle pause, not a frame-rate promise.
- Five consecutive camera failures stop the run. Earlier frames stay on disk.
- Cancel and interrupt keep saved frames. Status values: `preparing`, `capturing`, `completed`, `cancelled`, `failed`, `interrupted`.
- Capture does **not** score or reject frames for blur. Quality belongs to reconstruction.
- Tests use `FakeStillCamera` and a tiny JPEG. `flutter test` does not open a camera.

UI: `CaptureController` plus `CaptureScreen`, `CameraStage`, `FramingGuide`, `FrameCountSelector`, `CaptureProgressPanel`, `StabilityNotice`. Rear camera selection is in `rear_camera_selection.dart`. Camera errors are mapped in `camera_exception_mapper.dart`.

## Reconstruction architecture

The UI calls `ImageProcessingService.reconstruct`. `isAvailable` is `superResolution.isAvailable` only. `reconstruct` delegates only to `superResolution`. It does **not** call `alignment.align` first (that would register twice).

| Factory | Behavior |
|---|---|
| `ImageProcessingService.local()` | `LocalAlignmentService`, `LocalReconstructionService`, `LocalQualityService` |
| `ImageProcessingService.unavailable()` | Returns immediately, writes nothing |

`LocalReconstructionService` spawns an isolate. The first message from the isolate is the cancel `SendPort`. Progress maps have `type: progress`. Result maps have `type: result`. Only paths and JSON-shaped maps cross the isolate. Do not send native image objects.

Unit tests call `ReconstructionEngine.run` directly. One engine test covers the isolate service.

### Pipeline (`ReconstructionEngine`, version `1`)

Stages emitted as real work, not timers: preparing, analyzing, selecting a reference, estimating motion, aligning, rejecting, denoising, super-resolving when it runs, saving, then completed, failed, or cancelled.

1. **Load.** Snapshot original file lengths. Inspect one frame at a time and drop the bitmap. `inspectFrame` checks existence, emptiness, decode, minimum size (8 px), and bakes EXIF orientation. `decodeImage` can throw on short garbage (PSD decoder); `_tryDecode` catches that and treats the file as corrupt. Incompatible sizes are rejected, not stretched. The working size is the most common decoded size, then the larger area.
2. **Quality.** Laplacian sharpness, mean luminance, highlight clip (≥ 0.97), shadow clip (≤ 0.03), texture (standard deviation). A smooth image is not a defect. Blur rejection: median sharpness of non-rejected frames is above 0.01, this frame is under 0.2× that median, **and** absolute sharpness is under 0.008. Overexposure is a separate reason. If fewer than two frames are usable, fail and ask for a recapture. No PNG.
3. **Reference.** Try up to three highest-scoring usable frames. Keep the candidate that accepts the most others. A black border or a noisy frame must not become the only reference.
4. **Register** each other usable frame against that reference (`estimateTranslation`).
5. **Denoise** accepted frames (`weighted-robust-average`). One accepted frame is not a successful multi-frame result.
6. **Super-resolve** only when `_superResolutionSkipReason` returns null (`shift-and-add-ibp`).
7. **Save.** `denoised.png` via `writeBytesAtomic`, then decode it and check width and height. `super_resolution.png` only after the same check. On a successful denoise-only run, delete a stale `super_resolution.png`. `reconstruction.json` is written on success and on honest failure when the results directory can be created. If `outputDirectory` is an existing file, directory creation fails (storage-failure test). Cancel and failure do not leave an output PNG.

Original lengths are checked again at the end. A length change becomes a warning.

### Coordinate convention

Do not flip this.

`PlaneTransform`: source `(x, y)` matches reference `(x + dx, y + dy)` after the source is rotated by `angleDegrees` around its center. Fusion samples the source at `(x - dx, y - dy)`, then undoes the rotation.

Super-resolution splat places source pixel `(x, y)` at high-resolution `((x + dx) * scale, (y + dy) * scale)` with `scale = 2`. `dx = 0` lands on even pixels. `dx = 0.5` lands on odd pixels (`2x + 1`).

Synthetic low-resolution frames use the same model: `frame(x, y) = bilinear(highResolution, (x + dx) * 2, (y + dy) * 2)`.

Integer sampling is used when the angle is about 0 and the shift is within 0.02 of an integer. Otherwise sampling is bilinear.

### Registration (`estimateTranslation`)

Grayscale is Rec.709 luma in 0–1. `NaN` means the sample fell outside the frame. Integer differences must skip `NaN` samples. A rotated plane has `NaN` borders; forgetting the skip makes the angle search return `NaN` and stick at 0°.

- Both planes with standard deviation under 0.02: accept identity, `lowTexture: true`, no alias scan. Super-resolution is forbidden.
- Fast path only when zero-shift MAE is under `1e-6` and overlap is over 0.98. Then still run the alias scan. A 1–2° rotation of a smooth photo has a tiny MAE and must **not** take this path.
- Pyramid stops when a side is about 40 px or less. Angle search is full resolution when width ≤ 96. Otherwise it uses the coarsest pyramid level whose shorter side is still ≥ 64.
- Search radius is `min(4, levelWidth ~/ 2)`. Do not raise this toward `width/2`. A wide window locks onto aliases, rejects valid frames, and makes tests very slow.
- Angles tried: 0, −1, 1, −2, 2 degrees. Keep a non-zero angle only when it beats translation by at least 0.002 MAE. Subpixel search is ±1.0 at 0.25, then ±0.25 at 0.05, on the full-resolution plane.
- Reject when `|shift| > 0.40 * dimension` (“too large”), overlap `< 0.70`, or post-warp MAE `> 0.10`.
- Periodic alias: inside radius 12, a shift at least 3 px away whose MAE is within +0.012 of the best and overlap ≥ 0.5 sets `periodicAmbiguity`. If that flag is set and the shift magnitude is over 1.5, reject the frame. If the flag is set but the shift is near zero, accept for denoise and forbid super-resolution.
- This is one global translation plus a small rotation. It does not solve parallax, moving 3D scenes, or large perspective change. Homography is intentionally absent.

### Denoise

Per-frame integer weight `1000 / (0.02 + mae)`, clamped to 1..10000. `Uint32` channel sums. Outlier pixels are skipped when any channel differs from the reference by more than 42 after a median exposure gain clamped to `[0.75, 1.35]`. The reference pixel is always included, so a moving object does not ghost. Color is kept. Output size is the input size.

### Super-resolution gates

Checked in this order. The first failure skips 2× and keeps the denoise:

1. `allowSuperResolution` (advanced setting, default true).
2. Output pixels `4 * width * height` ≤ `maxSuperResolutionPixels` (default 4,000,000). A 12 MP frame stays native because 2× is about 48 MP.
3. No accepted frame is `lowTexture`.
4. No accepted frame has `periodicAmbiguity`.
5. No accepted frame has `|angle| > 0.35°`.
6. At least one non-reference accepted frame has fractional `|dx|` or `|dy| ≥ 0.12`.

Algorithm: bilinear shift-and-add, two iterative back-projection steps at gain 0.55, then a 12% blend toward the initial estimate. Coverage under 0.8 abandons super-resolution (warning, denoise kept). Holes are filled from the denoised image, not invented. Strategy strings: `multi-frame-denoise` or `multi-frame-super-resolution`.

### Advanced settings

Tune icon on the reconstruction screen: **Allow super-resolution**, **Reject outlier pixels**. Defaults are on. The screen shows a determinate `LinearProgressIndicator` only while a run is active (`key: reconstruction-progress`). Cancel is polled between frames and between super-resolution iterations. Dispose cancels. Do not show completed until the output file exists and its length is greater than 0. The file check is synchronous (`existsSync` / `lengthSync`) so widget tests are not stuck on a real `File` future inside `FakeAsync`. If super-resolution did not run, that stage shows a remove icon and says it was skipped. The result is labeled native-resolution denoise versus multi-frame super-resolution.

### Results screen

`InteractiveViewer`, `minScale` 0.8, `maxScale` 12, `FilterQuality.none`, no `cacheWidth`, so zoom is the saved pixels. Default view is the split compare (`_SplitClipper`: left fraction is the reconstruction). Segmented Original / Result / Compare. If both PNGs exist, a control switches Denoised and Super-resolved. **Fit to screen** resets the transform. **Export TIFF** re-encodes the PNG with `encodeTiff` beside the PNG. **Share** uses `SharePlus`. Linux throws `UnimplementedError`; the screen catches it and snackbars the saved path. Large-image rendering is file-backed. There is no generative enhancement.

## Theme

Material 3 dark. Background `#0B1212`, surface `#15201F`, teal `#2DD4BF`, danger `#FB7185`. `buildCrystalTheme()` in `lib/core/theme/crystal_theme.dart`. Match it. Do not introduce a second theme.

## Layout

```text
lib/main.dart                          local engine wired here
lib/app.dart                           MaterialApp, CaptureScreen
lib/app_dependencies.dart              AppScope
lib/core/errors/app_exception.dart
lib/core/storage/atomic_file.dart
lib/core/storage/session_store.dart
lib/core/theme/crystal_theme.dart
lib/core/utils/                        paths, frame names, session ids, JPEG size, JSON readers, formatters
lib/models/                            capture session, frame record, reconstruction result, quality, progress
lib/features/capture/                  camera, CaptureService, capture UI
lib/features/sessions/                 list, summary, viewer, thumbnails
lib/features/reconstruction/data/      engine, registration, fusion, inspection
lib/features/reconstruction/presentation/reconstruction_screen.dart
lib/features/results/presentation/results_screen.dart
lib/services/                          processing facade, local isolate, unavailable stubs
```

There is no `lib/services/image_denoising_service.dart` or separate orchestrator class. Denoise and super-resolution live in `frame_fusion.dart`. Orchestration is `ReconstructionEngine`.

## Dependencies

Resolved in `pubspec.lock`:

- `camera` 0.12.0+2
- `path_provider` 2.1.6
- `image` 4.10.2 (`decodeImage`, `encodePng`, `encodeJpg`, `encodeTiff`, `bakeOrientation`, `setPixelRgb`)
- `share_plus` 13.3.1 (`SharePlus.instance.share(ShareParams(...))`, `XFile` from `share_plus`)

`image` pixel channels are `num`. JPEG encoding writes EXIF when `image.exif.imageIfd.orientation` is set. Orientation 6 is a 90° rotation: `dst(x, y) = src(y, height - 1 - x)`.

## Tests

```bash
flutter pub get
flutter analyze
flutter test
```

Last green run: analyze clean, **55 tests passed**. Do not claim a later run passed unless it was executed.

`test/reconstruction_engine_test.dart` builds synthetic images with known shifts and noise: identical frames, integer translation, 2× subpixel grid versus bilinear upsampling, 2° rotation of two opposite squares, low texture, repetitive bars, size mismatch, JPEG orientation 6, blur and overexposure, corrupt and missing files, a moving object, partial overlap, failed registration, empty session, cancellation, blocked results path, all-corrupt, noise plus an edge, pixel budget, mixed subjects, isolate smoke test.

`test/reconstruction_service_test.dart` locks the unavailable engine: `alignment.calls == 0`, no output directory, `fromJson` round-trip, uncalibrated quality returns null.

`test/reconstruction_screen_test.dart` locks the unavailable UI and covers the scripted available path plus share.

Widget-test traps:

- `testWidgets` uses `FakeAsync`. `await Directory.createTemp` or `await File.exists` inside the test or inside a button handler never completes. Use `createTempSync`, `writeAsBytesSync`, `existsSync`, and `lengthSync`.
- `tester.pumpAndSettle` on `Image.file` or an indeterminate progress indicator can spin until the 10-minute timeout. Use a determinate indicator and a fixed `pump`.
- Do not `await` a `Completer` that the test completes only after `pump`. The scripted engine must finish synchronously.
- TIFF export in a widget test belongs inside `tester.runAsync`.
- The unavailable test must still find zero `LinearProgressIndicator` and zero `Icons.check_circle`.

Capture tests expect 16 frames where they drive a full run, and they use `expectLater` for async throws. The reconstruction button lives in the top card so it is on screen in an 800×600 test.

## How to run

On a phone with USB debugging:

```bash
flutter devices
flutter pub get
flutter run
```

Grant camera access. Microphone is not requested. Images stay in the app's private documents directory.

There was no physical 32-frame session and no phone attached when the engine was implemented. Synthetic tests are the validation that ran. To reconstruct a real session: open it, **Continue to reconstruction**, optionally use the tune icon, **Run reconstruction**, then compare with the slider and pinch zoom.

## Known limits

- Registration is translation plus at most about 2° of rotation. No ECC, ORB, or homography.
- A single global transform does not fix parallax or independently moving regions.
- No focus stacking and no generative fill. Different focus planes are reported, not stacked.
- Super-resolution is 2× only, and only inside the gates above. 12 MP bursts are native denoises.
- TIFF is an export of the saved PNG, not a separate reconstruction.
- Linux share is unimplemented by the plugin. The file is still saved.
- Peak memory has not been measured on a phone.
- A 12K effective-resolution claim still needs a photographed resolution target, a blur and sampling model checked against that target, subpixel shifts on the full sensor grid, a solver that fits in phone memory at that size, and an independent measurement. Pixel dimensions, PSNR, and high-frequency MAD are not that measurement.

## When changing the engine

- Keep the coordinate convention and the search radius of 4.
- Keep the identical-frame fast path at MAE `< 1e-6`. A looser threshold swallows small rotations.
- Keep the rotation gate near 0.002. The 2° two-square fixture beats translation by about 0.003. A gate of 0.008 rejects that real rotation. A gate near 0 lets noise pick a spurious angle.
- Skip `NaN` in integer `_difference`. Rotated planes store `NaN` outside the source.
- Blur uses the median sharpness, not the max. A hard edge or noise must not mark every normal frame as blurred.
- Do not widen super-resolution to 4× or 8× because a user asked for 12K.
- After engine or UI edits, run `flutter analyze` and `flutter test`. Capture tests must stay green.
