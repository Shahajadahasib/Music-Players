import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../licensing/license_controller.dart';
import 'screens/now_playing_screen.dart';
import 'screens/premium_screen.dart';

const String nowPlayingRouteName = '/now-playing';

/// Opens Now Playing on the root navigator (above the tab bar) once.
Future<void> openNowPlaying(BuildContext context) async {
  final nav = Navigator.of(context, rootNavigator: true);
  var onTop = false;
  nav.popUntil((route) {
    onTop = route.settings.name == nowPlayingRouteName;
    return true;
  });
  if (onTop) return;
  await nav.push(PageRouteBuilder<void>(
    settings: const RouteSettings(name: nowPlayingRouteName),
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const NowPlayingScreen(),
    transitionsBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
        child: child,
      );
    },
  ));
}

/// Pushes a page inside the current tab (keeps the tab bar + mini player).
Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

Future<void> openPremium(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PremiumScreen()));

/// Returns true when [feature] is unlocked; otherwise explains Premium.
bool requirePremium(BuildContext context, WidgetRef ref, PremiumFeature feature) {
  if (ref.read(licenseControllerProvider).allows(feature)) return true;
  openPremium(context);
  return false;
}

/// Opens an external https link (provider page, store, policy).
Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Couldn’t open the link.')),
    );
  }
}
