import 'package:flutter/material.dart';

/// Shared layout values for premium Apple Music / Spotify-style design.
abstract final class AppLayout {
  // ── Bottom clearance ────────────────────────────────────────────────────

  /// Space above scrollable content so list rows stay above the floating mini player.
  static const double contentBottomInsetWhenPlaying = 100;

  // ── Hero ────────────────────────────────────────────────────────────────

  /// Height of the featured hero card.
  static const double heroHeight = 230;

  // ── Card dimensions ─────────────────────────────────────────────────────

  /// Width of standard carousel cards (Made For You, Quick Picks horizontal).
  static const double cardWidth = 130;

  /// Height of carousel cards.
  static const double cardHeight = 200;

  /// Width of Recently Played cards.
  static const double recentCardWidth = 160;

  // ── Border radius system ────────────────────────────────────────────────

  /// Small: image thumbnails, mini chips.
  static const double cardRadiusSmall = 12.0;

  /// Medium: carousel cards.
  static const double cardRadiusMedium = 16.0;

  /// Large: hero card, dialogs.
  static const double cardRadiusLarge = 20.0;

  // ── Top padding ────────────────────────────────────────────────────────

  /// Top padding for home body (not needed in new design).
  static double homeBodyTopPadding(BuildContext context) => 0;

  static const double homeAppBarBottomSectionHeight = 0;
}
