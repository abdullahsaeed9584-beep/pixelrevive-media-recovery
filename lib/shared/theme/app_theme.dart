import 'package:flutter/material.dart';

class AppColors {
  // Accent color (Consistent across both modes)
  static const Color accentLime = Color(0xFFC6FF00);
  
  // Semantic colors
  static const Color accentOrange = Color(0xFFFFB703);
  static const Color destructive = Color(0xFFEF233C);

  // Dark Mode specific
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceHigh = Color(0xFF2C2C2C);
  static const Color darkTextPrimary = Color(0xFFF5F5F5);
  static const Color darkTextSecondary = Color(0xFFA0A0A0);

  // Light Mode specific
  static const Color lightBackground = Color(0xFFF3F4F6);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFE5E7EB);
  static const Color lightTextPrimary = Color(0xFF121212);
  static const Color lightTextSecondary = Color(0xFF555555);
}

class AppTheme {
  static ThemeData get light {
    final colorScheme = const ColorScheme.light(
      primary: AppColors.accentLime,
      onPrimary: AppColors.lightTextPrimary, // Dark text on lime green
      secondary: AppColors.accentLime,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      error: AppColors.destructive,
      surfaceContainerHighest: AppColors.lightSurfaceHigh,
      onSurfaceVariant: AppColors.lightTextSecondary,
    );
    
    return _buildTheme(colorScheme, AppColors.lightBackground);
  }

  static ThemeData get dark {
    final colorScheme = const ColorScheme.dark(
      primary: AppColors.accentLime,
      onPrimary: AppColors.darkBackground, // Dark text on lime green
      secondary: AppColors.accentLime,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      error: AppColors.destructive,
      surfaceContainerHighest: AppColors.darkSurfaceHigh,
      onSurfaceVariant: AppColors.darkTextSecondary,
    );
    
    return _buildTheme(colorScheme, AppColors.darkBackground);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme, Color scaffoldBackground) {
    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      scaffoldBackgroundColor: scaffoldBackground,
      colorScheme: colorScheme,
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontFamily: 'Inter',
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.surfaceContainerHighest, width: 1),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        tileColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        iconColor: colorScheme.onSurface,
        textColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        labelStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}
