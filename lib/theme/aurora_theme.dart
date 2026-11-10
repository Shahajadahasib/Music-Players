import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic colours for the "Aurora" design language, available in dark and
/// light variants via `context.palette`.
@immutable
class AuroraPalette extends ThemeExtension<AuroraPalette> {
  const AuroraPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.accent,
    required this.accentAlt,
    required this.accentWarm,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color accent;
  final Color accentAlt;
  final Color accentWarm;
  final Color success;
  final Color warning;
  final Color danger;

  static const dark = AuroraPalette(
    background: Color(0xFF0B0B10),
    surface: Color(0xFF15161F),
    surfaceRaised: Color(0xFF1D1F2C),
    surfaceSubtle: Color(0xFF111219),
    textPrimary: Color(0xFFF7F7FA),
    textSecondary: Color(0xFFA6A9B8),
    textTertiary: Color(0xFF6E7285),
    divider: Color(0xFF262838),
    accent: Color(0xFF6C7BFF),
    accentAlt: Color(0xFFA78BFA),
    accentWarm: Color(0xFFF472B6),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
  );

  static const light = AuroraPalette(
    background: Color(0xFFF7F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFEEEFF6),
    textPrimary: Color(0xFF12131C),
    textSecondary: Color(0xFF515569),
    textTertiary: Color(0xFF878BA0),
    divider: Color(0xFFE3E4EE),
    accent: Color(0xFF4655F0),
    accentAlt: Color(0xFF7C5CE6),
    accentWarm: Color(0xFFDB2777),
    success: Color(0xFF059669),
    warning: Color(0xFFB45309),
    danger: Color(0xFFDC2626),
  );

  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accentAlt, accentWarm],
      );

  /// Background tinted by the current artwork accent (Now Playing).
  LinearGradient ambient(Color tint) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [tint.withValues(alpha: 0.35), background, background],
        stops: const [0.0, 0.55, 1.0],
      );

  @override
  AuroraPalette copyWith() => this;

  @override
  AuroraPalette lerp(ThemeExtension<AuroraPalette>? other, double t) {
    if (other is! AuroraPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AuroraPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceSubtle: l(surfaceSubtle, other.surfaceSubtle),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      divider: l(divider, other.divider),
      accent: l(accent, other.accent),
      accentAlt: l(accentAlt, other.accentAlt),
      accentWarm: l(accentWarm, other.accentWarm),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
    );
  }
}

extension AuroraContext on BuildContext {
  AuroraPalette get palette =>
      Theme.of(this).extension<AuroraPalette>() ?? AuroraPalette.dark;
  TextTheme get text => Theme.of(this).textTheme;
}

abstract final class AuroraTheme {
  /// Set to false in tests so google_fonts never touches the network.
  static bool useGoogleFonts = true;

  static ThemeData dark() => _build(Brightness.dark, AuroraPalette.dark);
  static ThemeData light() => _build(Brightness.light, AuroraPalette.light);

  static TextTheme _textTheme(TextTheme base, AuroraPalette p) {
    final themed = useGoogleFonts ? GoogleFonts.plusJakartaSansTextTheme(base) : base;
    return themed
        .apply(bodyColor: p.textPrimary, displayColor: p.textPrimary)
        .copyWith(
          headlineLarge: themed.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: p.textPrimary,
          ),
          headlineMedium: themed.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: p.textPrimary,
          ),
          titleLarge: themed.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: p.textPrimary,
          ),
          titleMedium: themed.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
          bodyMedium: themed.bodyMedium?.copyWith(color: p.textSecondary),
          bodySmall: themed.bodySmall?.copyWith(color: p.textTertiary),
          labelSmall: themed.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        );
  }

  static ThemeData _build(Brightness brightness, AuroraPalette p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
    ).copyWith(
      primary: p.accent,
      onPrimary: Colors.white,
      secondary: p.accentAlt,
      tertiary: p.accentWarm,
      surface: p.background,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.surfaceSubtle,
      surfaceContainerLow: p.surfaceSubtle,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceRaised,
      surfaceContainerHighest: p.surfaceRaised,
      outline: p.divider,
      outlineVariant: p.divider,
      error: p.danger,
    );
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final text = _textTheme(base.textTheme, p);
    final radius = BorderRadius.circular(16);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: text,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        titleTextStyle: text.titleLarge,
      ),
      iconTheme: IconThemeData(color: p.textPrimary),
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: radius),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceRaised,
        hintStyle: TextStyle(color: p.textTertiary),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: p.accent.withValues(alpha: 0.7), width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surfaceSubtle,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accent.withValues(alpha: 0.18),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? p.textPrimary : p.textTertiary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? p.accent : p.textTertiary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surfaceSubtle,
        indicatorColor: p.accent.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: p.accent),
        unselectedIconTheme: IconThemeData(color: p.textTertiary),
        selectedLabelTextStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: p.textTertiary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.textPrimary,
        inactiveTrackColor: p.textPrimary.withValues(alpha: 0.15),
        secondaryActiveTrackColor: p.textPrimary.withValues(alpha: 0.32),
        thumbColor: p.textPrimary,
        overlayColor: p.textPrimary.withValues(alpha: 0.1),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.textTertiary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.textPrimary,
        contentTextStyle: TextStyle(color: p.background, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceRaised,
        side: BorderSide.none,
        labelStyle: text.labelLarge?.copyWith(color: p.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.divider,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : p.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceRaised,
        ),
      ),
    );
  }
}

String formatTrackDuration(Duration value) {
  final h = value.inHours;
  final m = value.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Time-aware greeting string.
String getGreeting([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 22) return 'Good evening';
  return 'Late night listening';
}
