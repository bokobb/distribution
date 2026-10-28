import 'package:flutter/material.dart';

/// Цвета как у веб-админки дистрибуции и CRM «Юг Сладости» (static/admin/assets/admin.css): шоколадная
/// шапка, пергаментный фон, малиновый — главное действие и тревога, желток — выделение.
class AppColors {
  static const chocolate = Color(0xFF2A1712);
  static const cream = Color(0xFFFFF6DA);
  static const paper = Color(0xFFF3F2E9);
  static const paperDeep = Color(0xFFEAE7DA);
  static const ink = Color(0xFF2A1712);
  static const inkSoft = Color(0xFF6B564B);
  static const crimson = Color(0xFFB9203C);
  static const crimsonSoft = Color(0xFFF9E3E7);
  static const yolk = Color(0xFFFFC646);
  static const ok = Color(0xFF2F6B3F);
  static const line = Color(0x1F2A1712);
}

ThemeData appTheme() {
  const radius = BorderRadius.all(Radius.circular(12));
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.crimson).copyWith(
    primary: AppColors.crimson,
    onPrimary: Colors.white,
    secondary: AppColors.yolk,
    onSecondary: AppColors.ink,
    surface: Colors.white,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkSoft,
    error: AppColors.crimson,
    outline: AppColors.line,
    outlineVariant: AppColors.line,
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'IBMPlexSans',
    scaffoldBackgroundColor: AppColors.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.chocolate,
      foregroundColor: AppColors.cream,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.ink, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'IBMPlexSans', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
