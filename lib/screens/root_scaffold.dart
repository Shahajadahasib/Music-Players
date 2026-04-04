import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/player_navigation.dart';
import '../widgets/mini_player.dart';
import 'home_screen.dart';

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _RootNavigatorObserver _navigatorObserver = _RootNavigatorObserver(
    onRouteChanged: () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    },
  );

  bool get _isPlayerRouteActive => _navigatorObserver.currentRouteName == '/player';

  Future<void> _openPlayerScreen() async {
    await pushPlayerScreenForNavigator(_navigatorKey.currentState);
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      builder: (_) => const HomeScreen(),
      settings: const RouteSettings(name: '/home'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never let the root route pop automatically on back press.
      // Instead, delegate to the inner Navigator first so PlayerScreen
      // (and any future nested routes) are dismissed correctly.
      // Only exit when the inner Navigator itself has nothing left to pop.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final innerNav = _navigatorKey.currentState;
        if (innerNav != null && innerNav.canPop()) {
          innerNav.pop();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Navigator(
                key: _navigatorKey,
                observers: [_navigatorObserver],
                onGenerateRoute: _onGenerateRoute,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                minimum: const EdgeInsets.only(bottom: 0),
                child: MiniPlayer(
                  onTap: _openPlayerScreen,
                  isPlayerRouteActive: _isPlayerRouteActive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RootNavigatorObserver extends NavigatorObserver {
  _RootNavigatorObserver({required this.onRouteChanged});

  final VoidCallback onRouteChanged;
  String? currentRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Only track explicitly named routes (screens).
    // Unnamed routes — modal bottom sheets, dialogs, etc. — must NOT
    // overwrite currentRouteName, otherwise isPlayerRouteActive flips to
    // false while a sheet is open and the MiniPlayer reappears on top.
    if (route.settings.name != null) {
      currentRouteName = route.settings.name;
      onRouteChanged();
    }
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRouteName = previousRoute?.settings.name;
    onRouteChanged();
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentRouteName = newRoute?.settings.name;
    onRouteChanged();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
