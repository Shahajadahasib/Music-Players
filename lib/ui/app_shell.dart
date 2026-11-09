import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../theme/aurora_theme.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/mini_player.dart';

/// Selected tab, exposed so screens can switch tabs (e.g. "Search" CTA).
final shellTabProvider = StateProvider<int>((ref) => 0);

/// Root layout: per-tab navigators (so artist/album pages keep the tab bar),
/// a bottom [NavigationBar] on phones and a [NavigationRail] on wide screens
/// (tablets, desktop web). The mini player sits above the navigation bar.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _navKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  static const _destinations = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: 'Home'),
    (icon: Icons.search_rounded, selected: Icons.saved_search_rounded, label: 'Search'),
    (icon: Icons.library_music_outlined, selected: Icons.library_music_rounded, label: 'Library'),
    (icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: 'Settings'),
  ];

  Widget _tabRoot(int i) => switch (i) {
        0 => const HomeScreen(),
        1 => const SearchScreen(),
        2 => const LibraryScreen(),
        _ => const SettingsScreen(),
      };

  void _select(int i) {
    final current = ref.read(shellTabProvider);
    if (i == current) {
      // Re-tapping a tab pops it to its root.
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      ref.read(shellTabProvider.notifier).state = i;
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    _listenForMessages();

    final tabs = IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < 4; i++)
          HeroControllerScope.none(
            child: Navigator(
              key: _navKeys[i],
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _tabRoot(i)),
            ),
          ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _navKeys[index].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (index != 0) {
          ref.read(shellTabProvider.notifier).state = 0;
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _Logo(),
                    ),
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selected),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: tabs),
                        const SafeArea(top: false, child: MiniPlayer()),
                      ],
                    ),
                  ),
                ],
              )
            : tabs,
        bottomNavigationBar: wide
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiniPlayer(),
                  NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: _select,
                    destinations: [
                      for (final d in _destinations)
                        NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selected),
                          label: d.label,
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// Errors and notices from the player surface as snack bars, once.
  void _listenForMessages() {
    ref.listen(playerControllerProvider.select((s) => s.errorMessage), (prev, next) {
      if (next == null || next == prev) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(next),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => ref.read(playerControllerProvider.notifier).retryPlayback(),
          ),
        ));
      ref.read(playerControllerProvider.notifier).clearError();
    });
    ref.listen(playerControllerProvider.select((s) => s.notice), (prev, next) {
      if (next == null || next == prev) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next), duration: const Duration(seconds: 3)));
    });
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: context.palette.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
    );
  }
}
