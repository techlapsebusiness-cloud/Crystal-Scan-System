import 'package:flutter/material.dart';

import 'package:microscopeapp/app.dart';
import 'package:microscopeapp/app_dependencies.dart';
import 'package:microscopeapp/core/storage/session_store.dart';
import 'package:microscopeapp/features/capture/data/capture_service.dart';
import 'package:microscopeapp/services/image_processing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SessionStore.openDefault();
  await store.markInterruptedSessions();
  runApp(
    CrystalScanApp(
      dependencies: AppDependencies(
        store: store,
        captureService: CaptureService(store: store),
        processing: ImageProcessingService.unavailable(),
      ),
    ),
  );
}
