import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: 'Cairo',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.surface,

    // ── AppBar ──────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),

    // ── Card ────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 2,
      shadowColor: AppColors.primary.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    // ── Input ────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.textSecond),
      hintStyle: TextStyle(fontFamily: 'Cairo', color: Colors.grey.shade400),
    ),

    // ── ElevatedButton ───────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ── TextButton ───────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600),
      ),
    ),

    // ── Chip ─────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primary.withOpacity(0.15),
      labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: Colors.grey.shade300),
    ),

    // ── Divider ──────────────────────────────
    dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1),

    // ── Text ─────────────────────────────────
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontFamily:'Cairo', fontSize:28, fontWeight:FontWeight.w700, color:AppColors.textPrimary),
      headlineMedium: TextStyle(fontFamily:'Cairo', fontSize:22, fontWeight:FontWeight.w700, color:AppColors.textPrimary),
      headlineSmall: TextStyle(fontFamily:'Cairo', fontSize:18, fontWeight:FontWeight.w600, color:AppColors.textPrimary),
      titleLarge:    TextStyle(fontFamily:'Cairo', fontSize:16, fontWeight:FontWeight.w600, color:AppColors.textPrimary),
      titleMedium:   TextStyle(fontFamily:'Cairo', fontSize:14, fontWeight:FontWeight.w600, color:AppColors.textPrimary),
      bodyLarge:     TextStyle(fontFamily:'Cairo', fontSize:15, color:AppColors.textPrimary),
      bodyMedium:    TextStyle(fontFamily:'Cairo', fontSize:13, color:AppColors.textSecond),
      bodySmall:     TextStyle(fontFamily:'Cairo', fontSize:12, color:AppColors.textSecond),
    ),

    // ── BottomNav ────────────────────────────
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecond,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: TextStyle(fontFamily:'Cairo', fontSize:11, fontWeight:FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontFamily:'Cairo', fontSize:11),
    ),

    // ── FloatingActionButton ─────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
  );
}
