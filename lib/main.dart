import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/root_scaffold.dart';
import 'services/audio_service.dart';
import 'services/hive_storage_service.dart';
import 'theme/aurora_scroll_behavior.dart';
import 'theme/aurora_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveStorageService.initialize();
  // iOS/Android: music session + background playback eligibility (see Info.plist).
  // Safe to call twice — [AudioService.initialize] is idempotent.
  await AudioService.instance.initialize();
  runApp(const ProviderScope(child: MusicPlayerApp()));
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final aurora = AuroraTheme.buildDarkTheme();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Music Player',
      scrollBehavior: const AuroraScrollBehavior(),
      theme: aurora.copyWith(
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: EdgeInsets.zero,
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
        ),
        tabBarTheme: TabBarThemeData(
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
          ),
          prefixIconColor: Colors.white.withValues(alpha: 0.65),
          suffixIconColor: Colors.white.withValues(alpha: 0.65),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: AuroraTheme.auroraBlue.withValues(alpha: 0.65),
            ),
          ),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: Colors.white.withValues(alpha: 0.85),
          linearTrackColor: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      home: const RootScaffold(),
    );
  }
}
