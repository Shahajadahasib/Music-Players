import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'config/app_config.dart';
import 'licensing/license_controller.dart';
import 'providers/settings_provider.dart';
import 'services/audio_service.dart';
import 'services/error_reporter.dart';
import 'services/hive_storage_service.dart';
import 'services/local_music_service.dart';
import 'theme/aurora_scroll_behavior.dart';
import 'theme/aurora_theme.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorReporter.install();

  // Notification / lock screen / Bluetooth / media-session integration.
  // Must run before the AudioPlayer is created.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.aurora.music.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );
  await HiveStorageService.initialize();
  await LocalMusicService.initialize();
  try {
    await AudioService.instance.initialize();
  } catch (e) {
    debugPrint('Audio session setup failed: $e');
  }
  runApp(const ProviderScope(child: MusicPlayerApp()));
}

class MusicPlayerApp extends ConsumerWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final premium = ref.watch(isPremiumProvider);
    // Light/system themes are a Premium feature; fall back to dark if the
    // licence was removed.
    final effective = premium ? mode : ThemeMode.dark;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      scrollBehavior: const AuroraScrollBehavior(),
      theme: AuroraTheme.light(),
      darkTheme: AuroraTheme.dark(),
      themeMode: effective,
      home: const AppShell(),
    );
  }
}
