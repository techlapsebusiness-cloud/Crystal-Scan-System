import 'package:flutter/widgets.dart';

import 'package:microscopeapp/core/storage/session_store.dart';
import 'package:microscopeapp/features/capture/data/capture_service.dart';
import 'package:microscopeapp/services/image_processing_service.dart';

class AppDependencies {
  const AppDependencies({
    required this.store,
    required this.captureService,
    required this.processing,
  });

  final SessionStore store;
  final CaptureService captureService;
  final ImageProcessingService processing;
}

class AppScope extends InheritedWidget {
  const AppScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return oldWidget.dependencies != dependencies;
  }
}
