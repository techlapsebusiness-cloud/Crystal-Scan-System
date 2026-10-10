# Crystal Scan

Crystal Scan captures a sequence of still photographs of a stationary object and stores the original frames for a later computational-photography stage. The first version is a capture and review tool. It does not reconstruct an image.

The intended subjects are electronic circuit boards, solder joints, copper traces, and other small surface detail, photographed with a phone on a tripod.

## What this version does

- Opens the rear camera and shows a live preview with a framing guide.
- Captures 16, 32, 64, or 128 frames, one shutter press at a time.
- Locks focus, exposure, flash, zoom, and lens for the session when the camera allows it.
- Saves originals under app storage at `crystal_scan/sessions/<session_id>/frames/`.
- Writes `session.json` atomically after each frame.
- Shows a session summary, thumbnails, and a single-frame viewer.
- Keeps a reconstruction screen that reports the engine as not implemented.

Autofocus and auto exposure run once before the first frame. They are not repeated between frames. ISO, shutter speed, focus distance, and the current exposure compensation are not recorded, because the camera plugin does not expose them without changing the image.

A tripod keeps the phone still. It does not by itself create the subpixel shifts a multi-frame reconstruction needs. This app does not claim that the saved burst contains independent information.

## Reconstruction

The processing API accepts the original file paths and returns a `ReconstructionResult`. The bundled engine is `UnavailableSuperResolutionService`. It does not decode frames, write an output file, or report an effective resolution.

Output pixel dimensions, optical resolution, and measured effective resolution are separate. Nothing in this version should be described as 12K, super-resolved, or enhanced.

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
