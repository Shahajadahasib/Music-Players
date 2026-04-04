import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium aurora palette: Apple Music / Spotify level.
abstract final class AuroraTheme {
  // ── Core colors ───────────────────────────────────────────────────────────

  static const Color deepSpace = Color(0xFF0D0D12);
  static const Color auroraBlue = Color(0xFF3B5BFE);
  static const Color auroraViolet = Color(0xFF8B5CF6);
  static const Color auroraMagenta = Color(0xFFD946EF);

  /// Elevated card / surface (Apple Music dark card).
  static const Color surfaceElevated = Color(0xFF1C1E2B);

  /// Subtle section background.
  static const Color surfaceSubtle = Color(0xFF141520);

  /// Glass highlights (mini player, frosted panels).
  static const Color glassHighlight = Color(0x33FFFFFF);
  static const Color glassBorder = Color(0x2EFFFFFF);

  /// Semantic text hierarchy.
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFA0A3B1);
  static const Color textTertiary = Color(0xFF6B6F80);
  static const Color dividerColor = Color(0xFF2A2D3E);

  // ── Gradients ─────────────────────────────────────────────────────────────

  static LinearGradient get backgroundGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          deepSpace,
          Color(0xFF10101A),
          deepSpace,
        ],
        stops: [0.0, 0.5, 1.0],
      );

  /// Album-art–driven ambient background gradient.
  static LinearGradient ambientGradient(Color accent) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accent.withValues(alpha: 0.18),
          deepSpace,
          deepSpace,
        ],
        stops: const [0.0, 0.45, 1.0],
      );

  static LinearGradient get playButtonGlow => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF60A5FA),
          Color(0xFFA78BFA),
          Color(0xFFE879F9),
        ],
      );

  static LinearGradient get heroOverlayGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00000000),
          Color(0x66000000),
          Color(0xCC000000),
        ],
        stops: [0.0, 0.4, 1.0],
      );

  static LinearGradient subtleShine(Color base) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          base.withValues(alpha: 0.35),
          base.withValues(alpha: 0.08),
        ],
      );

  // ── Typography (Plus Jakarta Sans) ────────────────────────────────────────

  static TextStyle get greetingText => GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.3,
      );

  static TextStyle get sectionTitleText => GoogleFonts.plusJakartaSans(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.3,
      );

  static TextStyle get sectionSeeAllText => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: auroraBlue,
      );

  static TextStyle get cardTitleText => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: 0,
      );

  static TextStyle get cardArtistText => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  static TextStyle get heroTitleText => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -0.5,
      );

  static TextStyle get heroSubText => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  static TextTheme textTheme(TextTheme base) {
    return GoogleFonts.plusJakartaSansTextTheme(base).apply(
      bodyColor: textPrimary.withValues(alpha: 0.92),
      displayColor: textPrimary,
    );
  }

  // ── Dark theme ────────────────────────────────────────────────────────────

  static ThemeData buildDarkTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: auroraViolet,
      brightness: Brightness.dark,
      primary: auroraBlue,
      secondary: auroraMagenta,
      surface: deepSpace,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base.copyWith(
        surface: deepSpace,
        surfaceContainerHighest: Colors.white.withValues(alpha: 0.08),
        surfaceContainerLow: surfaceSubtle,
        surfaceContainer: surfaceElevated,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        primary: auroraBlue,
        onPrimary: textPrimary,
      ),
      scaffoldBackgroundColor: deepSpace,
      textTheme: textTheme(ThemeData(brightness: Brightness.dark).textTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      iconTheme: const IconThemeData(color: textPrimary),
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
      ),
      splashColor: textPrimary.withValues(alpha: 0.1),
      highlightColor: textPrimary.withValues(alpha: 0.06),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: textTertiary,
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: textTertiary.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: textTertiary.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: auroraBlue.withValues(alpha: 0.6),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: auroraBlue,
        linearTrackColor: Colors.white.withValues(alpha: 0.1),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: textPrimary,
        unselectedLabelColor: textTertiary,
        indicatorColor: auroraBlue,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
    );
  }
}

String formatTrackDuration(Duration value) {
  final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Time-aware greeting string.
String getGreeting() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Good Morning';
  if (hour >= 12 && hour < 17) return 'Good Afternoon';
  if (hour >= 17 && hour < 21) return 'Good Evening';
  return 'Good Night';
}
