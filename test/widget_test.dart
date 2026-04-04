import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:music_player_app/main.dart';
import 'package:music_player_app/services/hive_storage_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final testDirectory = await Directory.systemTemp.createTemp('music_player_app_test_');
    await HiveStorageService.initialize(rootPath: testDirectory.path);
  });

  testWidgets('app boots with home screen tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MusicPlayerApp()));
    await tester.pumpAndSettle();

    expect(find.text('Your Music'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
  });
}
