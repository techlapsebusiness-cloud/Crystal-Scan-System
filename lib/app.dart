import 'package:flutter/material.dart';

import 'package:microscopeapp/app_dependencies.dart';
import 'package:microscopeapp/core/theme/crystal_theme.dart';
import 'package:microscopeapp/features/capture/presentation/capture_screen.dart';

class CrystalScanApp extends StatelessWidget {
  const CrystalScanApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        title: 'Crystal Scan',
        theme: buildCrystalTheme(),
        debugShowCheckedModeBanner: false,
        home: const CaptureScreen(),
      ),
    );
  }
}
