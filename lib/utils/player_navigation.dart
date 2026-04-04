import 'package:flutter/material.dart';

import '../screens/player_screen.dart';

/// Pushes [PlayerScreen] only when it is NOT already the top route.
///
/// Every song-tap and "Play All" button should call this instead of a raw
/// [Navigator.push], so only one PlayerScreen instance can ever exist in the
/// navigation stack at a time.
///
/// How the guard works:
///   [Navigator.popUntil] is called with a predicate that immediately returns
///   `true`, which makes it peek at the TOP route without popping anything.
///   This is synchronous, so it has no timing gap — unlike checking a flag
///   that is written inside [addPostFrameCallback].
Future<void> pushPlayerScreen(BuildContext context) {
  return pushPlayerScreenForNavigator(Navigator.of(context));
}

/// Same as [pushPlayerScreen] but for a [NavigatorState] (e.g. from a
/// [GlobalKey<NavigatorState>]) when no [BuildContext] is available below
/// that navigator.
Future<void> pushPlayerScreenForNavigator(NavigatorState? nav) {
  if (nav == null) return Future.value();

  String? topRouteName;
  nav.popUntil((route) {
    topRouteName = route.settings.name;
    return true;
  });

  if (topRouteName == '/player') return Future.value();

  return nav.push(
    MaterialPageRoute<void>(
      builder: (_) => const PlayerScreen(),
      settings: const RouteSettings(name: '/player'),
    ),
  );
}
