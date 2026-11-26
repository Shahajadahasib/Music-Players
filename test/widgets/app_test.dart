import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/licensing/license_controller.dart';
import 'package:music_player_app/licensing/license_store.dart';
import 'package:music_player_app/main.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/providers/source_providers.dart';
import 'package:music_player_app/services/hive_storage_service.dart';
import 'package:music_player_app/sources/music_source.dart';
import 'package:music_player_app/theme/aurora_theme.dart';

import '../helpers.dart';
import '../licensing/licensing_test.dart' show FakeGateway;

FakeSource _audius() => FakeSource(
      'audius',
      featured: [
        song('t1', title: 'Fixture Trending One', artist: 'Fixture Artist', sourceId: 'audius'),
        song('t2', title: 'Fixture Trending Two', artist: 'Fixture Artist', sourceId: 'audius'),
      ],
      results: [song('a1', title: 'Fixture Night Drive', artist: 'Fixture Band', seconds: 200, sourceId: 'audius')],
    );

FakeSource _catalogue() => FakeSource(
      'itunes',
      fullTracks: false,
      results: [
        song('itunes:9', title: 'Fixture Catalogue Only', artist: 'Famous Fixture',
            sourceId: 'itunes', playability: Playability.none, externalUrl: 'https://music.example/9'),
      ],
    );

Widget _app({bool premium = false, List<MusicSource>? sources}) => ProviderScope(
      overrides: [
        availableSourcesProvider.overrideWithValue(sources ?? [_audius(), _catalogue()]),
        // No network in tests: every resolvable stream counts as verified.
        streamVerifierProvider.overrideWith((ref) => FakeVerifier()),
        licenseControllerProvider.overrideWith((ref) => LicenseController(
              store: MemoryLicenseStore(),
              gateway: FakeGateway(available: false),
              publicKey: '',
              paidUpfront: premium,
            )),
      ],
      child: const MusicPlayerApp(),
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(() async {
    AuroraTheme.useGoogleFonts = false;
    final dir = await Directory.systemTemp.createTemp('app_test_');
    await HiveStorageService.initialize(rootPath: dir.path);
  });

  testWidgets('boots into Home with navigation and real featured data', (t) async {
    await t.pumpWidget(_app());
    await _settle(t);

    for (final label in ['Home', 'Search', 'Library', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Trending now'), findsOneWidget);
    expect(find.text('Fixture Trending One'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);
  });

  testWidgets('search shows merged results with honest availability badges', (t) async {
    await t.pumpWidget(_app());
    await _settle(t);
    await t.tap(find.text('Search').last);
    await _settle(t);

    await t.enterText(find.byType(TextField), 'fixture');
    await t.pump(const Duration(milliseconds: 500));
    await _settle(t);

    expect(find.text('Fixture Night Drive'), findsOneWidget);
    expect(find.text('Fixture Catalogue Only'), findsOneWidget);
    expect(find.text('Not streamable'), findsOneWidget);
    expect(find.text('Full track'), findsOneWidget, reason: 'verified stream');
    expect(find.textContaining('Fake audius'), findsWidgets, reason: 'provider name is shown');

    // Tapping a catalogue-only song with no authorised stream explains why
    // and offers the provider link instead of playing something else.
    await t.tap(find.text('Fixture Catalogue Only'));
    await _settle(t);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Original recording unavailable')),
      findsOneWidget,
    );
    expect(find.text('Open in Apple Music'), findsOneWidget);
  });

  testWidgets('free plan: 4th playlist and light theme require Premium', (t) async {
    // Real file I/O must run outside the fake-async test zone.
    await t.runAsync(() async {
      for (final n in ['A', 'B', 'C']) {
        await HiveStorageService.createPlaylist(n);
      }
    });
    await t.pumpWidget(_app());
    await _settle(t);
    await t.tap(find.text('Library').last);
    await _settle(t);
    expect(find.text('3/3 on the free plan'), findsOneWidget);
    await t.tap(find.byTooltip('New playlist'));
    await _settle(t);
    expect(find.text('Unlock Premium').evaluate().isNotEmpty || find.text('Aurora Music Premium').evaluate().isNotEmpty, isTrue);
    await t.tap(find.byType(CloseButton));
    await _settle(t);

    await t.tap(find.text('Settings').last);
    await _settle(t);
    await t.tap(find.text('Light'));
    await _settle(t);
    expect(find.text('Aurora Music Premium'), findsOneWidget);
  });

  testWidgets('premium screen rejects an invalid licence key', (t) async {
    await t.pumpWidget(_app());
    await _settle(t);
    await t.tap(find.text('Settings').last);
    await _settle(t);
    await t.tap(find.text('Unlock Premium'));
    await _settle(t);
    await t.scrollUntilVisible(find.byType(TextField), 200, scrollable: find.byType(Scrollable).last);
    await t.enterText(find.byType(TextField), 'AURORA1.fake.key');
    await t.ensureVisible(find.text('Activate'));
    await t.tap(find.text('Activate'));
    await _settle(t);
    expect(find.text('That licence key isn’t valid.'), findsOneWidget);
  });

  testWidgets('premium users can switch to the light theme', (t) async {
    await t.pumpWidget(_app(premium: true));
    await _settle(t);
    await t.tap(find.text('Settings').last);
    await _settle(t);
    await t.tap(find.text('Light'));
    await _settle(t);
    final ctx = t.element(find.text('Appearance'));
    expect(Theme.of(ctx).brightness, Brightness.light);
  });

  testWidgets('a named song with no authorised original shows "Original recording unavailable" and never plays a cover',
      (t) async {
    final catalogue = FakeSource('itunes', fullTracks: false, results: [
      song('itunes:7', title: 'Perfect', artist: 'Ed Sheeran', seconds: 263, sourceId: 'itunes',
          playability: Playability.none, externalUrl: 'https://music.example/7'),
    ]);
    final audius = FakeSource('audius', results: [
      song('cover', title: 'Perfect (Violin Cover)', artist: 'Strings Fixture', seconds: 250, sourceId: 'audius'),
    ]);
    await t.pumpWidget(_app(sources: [audius, catalogue]));
    await _settle(t);
    await t.tap(find.text('Search').last);
    await _settle(t);
    await t.enterText(find.byType(TextField), 'perfect ed sheeran');
    await t.pump(const Duration(milliseconds: 500));
    await _settle(t);

    expect(find.text('Best match'), findsOneWidget);
    expect(find.text('Original recording unavailable.'), findsOneWidget);
    expect(find.text('Other songs'), findsOneWidget);
    expect(find.text('Perfect (Violin Cover)'), findsOneWidget);

    await t.tap(find.text('Perfect').first);
    await _settle(t);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Original recording unavailable')),
      findsOneWidget,
      reason: 'explains instead of playing',
    );
    await t.tap(find.text('Close'));
    await _settle(t);
    expect(find.byTooltip('Pause'), findsNothing, reason: 'nothing started playing');
  });
}
