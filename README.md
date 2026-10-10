# Crystal Scan

Crystal Scan captures a sequence of still photographs of a stationary object and reconstructs a cleaner image on the device. The same pipeline is used for circuits, plants, documents, textures, and other ordinary photographs. The user does not pick a subject category.

A tripod keeps the phone still. It does not by itself create the subpixel shifts a resolution increase needs. Capturing more frames does not automatically raise resolution, and this app does not claim a 12K result.

## What this version does

- Opens the rear camera and shows a live preview with a framing guide.
- Captures 16, 32, 64, or 128 frames, one shutter press at a time.
- Locks focus, exposure, flash, zoom, and lens for the session when the camera allows it.
- Saves originals under app storage at `crystal_scan/sessions/<session_id>/frames/`.
- Writes `session.json` atomically after each frame.
- Shows a session summary, thumbnails, and a single-frame viewer.
- Reconstructs a saved session locally: quality checks, intensity registration, robust averaging, and 2× shift-and-add only when the frames contain a useful subpixel shift and the output fits a pixel budget.

Autofocus and auto exposure run once before the first frame. They are not repeated between frames. ISO, shutter speed, focus distance, and the current exposure compensation are not recorded, because the camera plugin does not expose them without changing the image.

A tripod keeps the phone still. It does not by itself create the subpixel shifts a multi-frame reconstruction needs. This app does not claim that the saved burst contains independent information.

## Reconstruction

Open a saved session and tap **Continue to reconstruction**, then **Run reconstruction**. Processing runs in a background isolate. Progress follows the stage that is actually running. Cancel stops the run before an output image is written.

Results are stored beside the originals:

```text
crystal_scan/sessions/<session_id>/
  frames/frame_0001.jpg
  results/denoised.png
  results/super_resolution.png   # only when 2× reconstruction ran
  results/reconstruction.json
```

Original JPEGs are opened read-only. The results screen compares the reference frame with the reconstruction, zooms without a display downsample, and can write a TIFF or share the PNG. On a desktop build without a share sheet, sharing reports that the file is already saved.

`denoised.png` is a native-resolution robust average. `super_resolution.png` is a separate 2× shift-and-add with two back-projection steps. If the shifts are whole pixels, the texture is ambiguous, a rotation was required, or a 2× image would exceed four million pixels, only the denoise is saved. Output pixel dimensions are not a measurement of effective optical resolution. That is stated on the result.

Registration is a coarse-to-fine intensity search for translation, plus a rotation of at most two degrees. It is not a homography and it does not solve parallax. Focus stacking and generative enhancement are not part of this pipeline.

The implementation uses Dart and `package:image`. `opencv_dart` is not used, so the same code runs under `flutter test` without a native OpenCV build. Feature matching and ECC are not available.

## Reconstruct a 32-frame session

1. Capture 32 frames, or open an existing session from the session list.
2. On the summary, tap **Continue to reconstruction**.
3. Leave **Allow super-resolution** on unless you only want the denoise. The control is under the tune icon.
4. Tap **Run reconstruction** and wait until the result screen opens. The run is not finished while the output file is missing.
5. Compare with the slider, then pinch to zoom. Fit returns to the full frame.
6. The reference frame is the original JPEG. The reconstruction is the PNG named above.

A 12-megapixel capture stays at native resolution: a 2× image would be about 48 megapixels, past the working limit. That limit is intentional. It is not a 12K reconstruction that was scaled back down.

## What is still required before a 12K claim

Effective resolution has not been measured on a resolution target. Pixel dimensions, PSNR, and high-frequency MAD do not replace that measurement. A genuine 12K claim would also need a validated blur and sampling model, subpixel shifts on the full sensor grid, a solver that fits in phone memory at that size, and an independent target measurement. None of those are done here.

## Run on an Android phone

1. Enable Developer options and USB debugging on the phone.
2. Connect the phone and accept the debugging prompt.
3. From this directory:

```bash
flutter devices
flutter pub get
flutter run
```

4. When Android asks, allow camera access. The app does not request microphone access.
5. Put the phone on a tripod, frame the board, choose a frame count, and tap the shutter.
6. Leave the board and the lighting alone until the summary appears.

Images stay in the app's private documents directory. A file manager can reach them through Android's app storage for Crystal Scan. The session summary also shows the directory path.

`flutter test` does not open a camera. The capture pipeline is tested with a fake camera.

## Checks

```bash
flutter pub get
flutter analyze
flutter test
```
# Crystal-Scan-System
