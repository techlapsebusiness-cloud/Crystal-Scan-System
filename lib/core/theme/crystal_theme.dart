import 'package:flutter/material.dart';

const Color crystalTeal = Color(0xFF2DD4BF);
const Color crystalTealInk = Color(0xFF04211E);
const Color crystalBackground = Color(0xFF0B1212);
const Color crystalSurface = Color(0xFF15201F);
const Color crystalWarning = Color(0xFFFBBF24);
const Color crystalDanger = Color(0xFFFB7185);

ThemeData buildCrystalTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: crystalTeal,
    brightness: Brightness.dark,
  ).copyWith(
    primary: crystalTeal,
    onPrimary: crystalTealInk,
    surface: crystalSurface,
    onSurface: const Color(0xFFE7F4F1),
    error: crystalDanger,
    onError: const Color(0xFF2A0A12),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: crystalBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: crystalBackground,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: crystalSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: crystalTeal,
        foregroundColor: crystalTealInk,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: crystalTeal,
        side: const BorderSide(color: crystalTeal),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: crystalTeal),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}
