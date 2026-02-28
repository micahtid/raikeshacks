import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  // Accent
  static const Color primary = Color(0xFFCDC9EC);
  static const Color onPrimary = Color(0xFF242422);

  // Text hierarchy
  static const Color textPrimary = Color(0xFFEAE8E3);
  static const Color textSecondary = Color(0xFFA5A39B);
  static const Color textTertiary = Color(0xFF6E6D68);

  // Surfaces
  static const Color surface = Color(0xFF262624);
  static const Color surfaceGray = Color(0xFF242422);
  static const Color surfaceLightBlue = Color(0xFF32313E);
  static const Color surfaceMediumBlue = Color(0xFF3A394A);

  // Borders
  static const Color border = Color(0xFF40403C);
  static const Color divider = Color(0xFF40403C);
  static const Color inactive = Color(0xFF4A4A46);

  // Icons
  static const Color icon = Color(0xFFEAE8E3);

  // Danger
  static const Color danger = Color(0xFFE85D5D);
}

abstract final class AppRadius {
  static const double button = 12.0;
  static const double card = 12.0;
  static const double bubble = 20.0;
  static const double searchBar = 22.0;
  static const double avatar = 16.0;
  static const double progressBar = 4.0;
}

abstract final class AppSpacing {
  static const double screenPadding = 24.0;
  static const double sectionGapLarge = 40.0;
  static const double sectionGapMedium = 32.0;
  static const double sectionGapSmall = 22.0;
  static const double listItemGap = 8.0;
  static const double buttonHeight = 48.0;
  static const double selectionItemHeight = 52.0;
  static const double avatarSize = 40.0;
  static const double progressBarHeight = 8.0;
  static const double searchBarHeight = 44.0;
}

ThemeData buildAppTheme() {
  final textTheme = GoogleFonts.soraTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.surface,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.divider,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
    ),
    textTheme: textTheme.copyWith(
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyMedium: textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      bodySmall: textTheme.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textTertiary,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.onPrimary,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.sora(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        minimumSize: const Size(double.infinity, AppSpacing.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: GoogleFonts.sora(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border, width: 0.5),
        minimumSize: const Size(0, AppSpacing.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: GoogleFonts.sora(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: GoogleFonts.sora(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceGray,
      hintStyle: GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textTertiary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surfaceGray,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      margin: EdgeInsets.zero,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.divider,
      linearMinHeight: AppSpacing.progressBarHeight,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 0.5,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceGray,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceLightBlue,
      contentTextStyle: GoogleFonts.sora(
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
