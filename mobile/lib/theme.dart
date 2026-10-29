import 'package:flutter/material.dart';

/// Цвета по макетам design/mobile (README, «Дизайн-токены»): светлая и спокойная тема, один акцент — индиго,
/// белые карточки на сером фоне; зелёный — доставлено и сумма сходится, янтарный — частично и долг, красный —
/// отказ и больше суммы.
class AppColors {
  /// Кнопки, маршрут, выбранная вкладка.
  static const accent = Color(0xFF4136F1);

  /// Нажатие и текст-ссылки.
  static const accentPressed = Color(0xFF3329D6);

  /// Подложка акцента: выбранный фильтр, кружок с буквами имени.
  static const accentSoft = Color(0xFFEEEDFE);

  static const text = Color(0xFF101318);

  /// Подписи полей ввода.
  static const label = Color(0xFF3D434D);

  /// Второй текст: подписи, адреса.
  static const text2 = Color(0xFF5C6370);

  /// Только значки.
  static const icon = Color(0xFF8C929C);

  static const line = Color(0xFFE8EAEE);

  /// Разделитель строк внутри карточки.
  static const divider = Color(0xFFEDEFF2);

  /// Рамка поля ввода.
  static const field = Color(0xFFE1E4EA);

  /// Заливка вторых кнопок и счётчиков.
  static const fill = Color(0xFFF1F2F5);

  /// Фон экрана; карточки белые.
  static const bg = Color(0xFFF4F5F7);
  static const card = Colors.white;

  static const ok = Color(0xFF12805C);
  static const okBg = Color(0xFFE7F5EF);
  static const warn = Color(0xFF9A5B00);
  static const warnBg = Color(0xFFFFF4DF);
  static const err = Color(0xFFC4291C);
  static const errBg = Color(0xFFFDECEA);
}

/// Тень белой карточки на сером фоне.
const cardShadow = [BoxShadow(color: Color(0x0F101318), blurRadius: 2, offset: Offset(0, 1))];

/// Суммы и время — моноширинными цифрами, чтобы столбцы не прыгали.
const tabular = [FontFeature.tabularFigures()];

ThemeData appTheme() {
  const r12 = BorderRadius.all(Radius.circular(12));
  const r14 = BorderRadius.all(Radius.circular(14));
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentSoft,
    onPrimaryContainer: AppColors.accentPressed,
    secondary: AppColors.accent,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.accentSoft,
    onSecondaryContainer: AppColors.accentPressed,
    surface: AppColors.card,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.text2,
    surfaceContainerHighest: AppColors.fill,
    error: AppColors.err,
    outline: AppColors.field,
    outlineVariant: AppColors.line,
  );
  // Шрифт по макету: 28/34 — заголовок экрана, 22/28 — суммы, 18/24 — заголовок карточки, 16/22 — кнопки,
  // 15/21 — основной текст, 13/18 — подписи, 11/14 — нижнее меню.
  TextStyle s(double size, double height, FontWeight weight, [Color color = AppColors.text, double spacing = 0]) =>
      TextStyle(
          // явно: стили кнопок, шапок и чипов берутся отсюда мимо ThemeData.fontFamily
          fontFamily: 'Inter',
          fontSize: size,
          height: height / size,
          fontWeight: weight,
          color: color,
          letterSpacing: spacing,
          fontFeatures: tabular);
  final text = TextTheme(
    headlineLarge: s(30, 36, FontWeight.w700, AppColors.text, -0.6),
    headlineMedium: s(28, 34, FontWeight.w700, AppColors.text, -0.56),
    headlineSmall: s(22, 28, FontWeight.w700, AppColors.text, -0.3),
    titleLarge: s(18, 24, FontWeight.w700),
    titleMedium: s(16, 22, FontWeight.w600),
    titleSmall: s(15, 21, FontWeight.w600),
    bodyLarge: s(15, 21, FontWeight.w400),
    bodyMedium: s(15, 21, FontWeight.w400),
    bodySmall: s(13, 18, FontWeight.w400, AppColors.text2),
    labelLarge: s(16, 22, FontWeight.w600),
    labelMedium: s(13, 18, FontWeight.w600, AppColors.label),
    labelSmall: s(11, 14, FontWeight.w600, AppColors.text2),
  );
  final button = text.labelLarge!;
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Inter',
    textTheme: text,
    scaffoldBackgroundColor: AppColors.bg,
    dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0x29101318),
      elevation: 0.6,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.icon,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: AppColors.text2),
      floatingLabelStyle: const TextStyle(color: AppColors.accentPressed),
      hintStyle: const TextStyle(color: AppColors.icon),
      border: const OutlineInputBorder(borderRadius: r14, borderSide: BorderSide(color: AppColors.field, width: 1.5)),
      enabledBorder:
          const OutlineInputBorder(borderRadius: r14, borderSide: BorderSide(color: AppColors.field, width: 1.5)),
      focusedBorder: const OutlineInputBorder(borderRadius: r14, borderSide: BorderSide(color: AppColors.accent, width: 2)),
      errorBorder: const OutlineInputBorder(borderRadius: r14, borderSide: BorderSide(color: AppColors.err, width: 1.5)),
      focusedErrorBorder:
          const OutlineInputBorder(borderRadius: r14, borderSide: BorderSide(color: AppColors.err, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFC9CDD5),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: r14),
        textStyle: button,
      ),
    ),
    // Вторая кнопка — серая заливка без рамки.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.fill,
        foregroundColor: AppColors.text,
        disabledForegroundColor: AppColors.icon,
        side: BorderSide.none,
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: r14),
        textStyle: button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentPressed,
        minimumSize: const Size(44, 44),
        shape: const RoundedRectangleBorder(borderRadius: r12),
        textStyle: text.titleSmall,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.card,
      selectedColor: AppColors.accentSoft,
      side: const BorderSide(color: AppColors.line),
      shape: const StadiumBorder(),
      labelStyle: text.bodySmall!.copyWith(color: AppColors.text, fontWeight: FontWeight.w600),
      secondaryLabelStyle: text.bodySmall!.copyWith(color: AppColors.accentPressed, fontWeight: FontWeight.w600),
      checkmarkColor: AppColors.accentPressed,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.fill,
        selectedBackgroundColor: AppColors.card,
        selectedForegroundColor: AppColors.text,
        foregroundColor: AppColors.text2,
        side: BorderSide.none,
        textStyle: text.titleSmall,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.text,
      contentTextStyle: text.bodyMedium!.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: r14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium!.copyWith(color: AppColors.text2),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r14),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
  );
}
