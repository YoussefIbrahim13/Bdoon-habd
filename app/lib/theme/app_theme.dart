import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Design tokens — single source of truth for the premium dark visual language.
/// ---------------------------------------------------------------------------

abstract final class AppColors {
  // Deep obsidian, not pure black.
  static const bg = Color(0xFF0E0F14);
  static const surface = Color(0xFF161821);
  static const surfaceActive = Color(0xFF1A1E2E);

  // Glass fills / hairline strokes.
  static const glassTint = Color(0x14FFFFFF); // 8% white
  static const glassFill = Color(0x0FFFFFFF); // 6% white
  static const stroke = Color(0x1FFFFFFF); // 12% white

  // Accents.
  static const electricBlue = Color(0xFF3D9BFF);
  static const neonPurple = Color(0xFFA855F7);
  static const emerald = Color(0xFF34D399);
  static const emeraldDeep = Color(0xFF059669);
  static const ruby = Color(0xFFFB7185);
  static const rubyDeep = Color(0xFFE11D48);
  static const amber = Color(0xFFFBBF24);
  static const amberDeep = Color(0xFFD97706);

  static const textPrimary = Color(0xFFF4F5F7);
  static const textSecondary = Color(0xFF9AA3B2);

  /// Per-player neon identity (seat order): cyan, purple, neon green,
  /// neon pink. Shared by the setup fields and the in-game scoreboard so a
  /// player's color follows them from the lobby into the match.
  static const playerAccents = [
    Color(0xFF22D3EE),
    Color(0xFFA855F7),
    Color(0xFF34F58A),
    Color(0xFFFF4FD8),
  ];
}

abstract final class AppGradients {
  /// Active player turn / primary actions.
  static const turn = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.electricBlue, AppColors.neonPurple],
  );

  /// Smart Judge: verdict "true".
  static const truth = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.emerald, AppColors.emeraldDeep],
  );

  /// Smart Judge: verdict "false" / destructive actions.
  static const falsehood = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.ruby, AppColors.rubyDeep],
  );

  /// Smart Judge: verdict "uncertain".
  static const uncertain = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.amber, AppColors.amberDeep],
  );

  /// Inactive hairline (lerp-compatible with [turn] for implicit animations).
  static const idle = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.stroke, AppColors.stroke],
  );
}

abstract final class AppRadii {
  static const card = 28.0;
  static const button = 22.0;
  static const field = 18.0;
  static const sheet = 32.0;
}

abstract final class AppShadows {
  /// Soft colored glow used behind gradient surfaces.
  static List<BoxShadow> glow(Color color, {double alpha = .35, double blur = 28}) => [
        BoxShadow(
          color: color.withValues(alpha: alpha),
          blurRadius: blur,
          offset: const Offset(0, 10),
        ),
      ];

  /// Neutral elevation for cards on the obsidian background.
  static const soft = [
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 12)),
  ];
}

/// Typography helpers.
///
/// Both families are bundled as variable fonts, so the weight axis is set
/// explicitly via [FontVariation] (plain [FontWeight] alone would render the
/// default instance).
abstract final class AppText {
  /// Cairo — Arabic-first UI text (also covers Latin).
  static TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? height,
    double? spacing,
  }) =>
      TextStyle(
        fontFamily: 'Cairo',
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        color: color,
        height: height,
        letterSpacing: spacing,
      );

  /// Outfit — large legible numerals (scoreboard, timers) and English accents.
  static TextStyle number({
    double size = 44,
    FontWeight weight = FontWeight.w800,
    Color color = AppColors.textPrimary,
    double? spacing,
  }) =>
      TextStyle(
        fontFamily: 'Outfit',
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        color: color,
        height: 1.0,
        letterSpacing: spacing,
      );
}

abstract final class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.electricBlue,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.bg,
      error: AppColors.rubyDeep,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: 'Cairo',
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassFill,
        hintStyle: AppText.ui(color: AppColors.textSecondary, size: 14),
        labelStyle: AppText.ui(color: AppColors.textSecondary, size: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.electricBlue, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceActive,
        contentTextStyle: AppText.ui(size: 14, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.stroke),
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.electricBlue),
    );
  }
}
