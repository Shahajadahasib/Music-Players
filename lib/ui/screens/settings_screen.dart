import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../licensing/license_controller.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/source_providers.dart';
import '../../services/hive_storage_service.dart';
import '../../sources/music_source.dart';
import '../../theme/aurora_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final license = ref.watch(licenseControllerProvider);
    final sources = ref.watch(availableSourcesProvider);
    final diag = ref.watch(playerControllerProvider.select((s) => s.diagnostics));
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: Semantics(header: true, child: const Text('Settings'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Premium ─────────────────────────────────────────────────
          if (!AppConfig.isPaidUpfront)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(gradient: p.brandGradient, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.workspace_premium_rounded, color: Colors.white),
                  ),
                  title: Text(license.isPremium ? 'Premium is active' : 'Unlock Premium'),
                  subtitle: Text(license.isPremium
                      ? 'Thank you for supporting ${AppConfig.appName}.'
                      : 'One-time purchase · no subscription'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openPremium(context),
                ),
              ),
            ),

          // ── Appearance ──────────────────────────────────────────────
          const SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('System')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (v) {
                final mode = v.first;
                if (mode != ThemeMode.dark && !requirePremium(context, ref, PremiumFeature.themes)) return;
                ref.read(settingsProvider.notifier).setThemeMode(mode);
              },
            ),
          ),

          // ── Sources ─────────────────────────────────────────────────
          const SectionHeader(
            'Music sources',
            subtitle: 'Only providers whose terms allow this app are listed',
          ),
          for (final s in sources)
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              value: !settings.disabledSources.contains(s.id),
              title: Text(s.info.displayName),
              subtitle: Text(_describe(s.info)),
              onChanged: (on) {
                final enabled = sources.where((x) => !settings.disabledSources.contains(x.id)).length;
                if (!on && enabled <= 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Keep at least one source enabled.')),
                  );
                  return;
                }
                ref.read(settingsProvider.notifier).setSourceEnabled(s.id, on);
                ref.read(searchAggregatorProvider).clearCache();
                ref.invalidate(featuredProvider);
              },
            ),

          // ── Data & privacy ──────────────────────────────────────────
          const SectionHeader('Data & privacy'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.shield_outlined),
            title: const Text('How your data is handled'),
            subtitle: const Text('No account, no tracking. Library stays on this device.'),
            onTap: () => _showPrivacy(context),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.history_toggle_off_rounded),
            title: const Text('Clear listening history'),
            onTap: () async {
              await HiveStorageService.clearHistory();
              if (context.mounted) _snack(context, 'History cleared');
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear search cache'),
            onTap: () {
              ref.read(searchAggregatorProvider).clearCache();
              _snack(context, 'Search cache cleared');
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.delete_forever_outlined, color: p.danger),
            title: Text('Delete all my data', style: TextStyle(color: p.danger)),
            subtitle: const Text('Favourites, playlists, history and settings on this device'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Delete all data?'),
                  content: const Text(
                    'This permanently erases your library from this device. Your Premium purchase is not affected and can be restored.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) {
                await HiveStorageService.clearAllUserData();
                ref.invalidate(playerControllerProvider);
                ref.invalidate(settingsProvider);
                if (context.mounted) _snack(context, 'All data deleted');
              }
            },
          ),

          // ── Diagnostics ─────────────────────────────────────────────
          const SectionHeader('Playback diagnostics', subtitle: 'Measured on this device · never uploaded'),
          _kv(context, 'Median start time',
              diag.medianStartupMs == null ? '—' : '${diag.medianStartupMs} ms (${diag.startupSamplesMs.length} plays)'),
          _kv(context, 'Rebuffering events', '${diag.rebufferCount}'),
          _kv(context, 'Automatic source fallbacks', '${diag.fallbackCount}'),
          _kv(context, 'Tracks that could not play', '${diag.failedCount}'),

          // ── About ───────────────────────────────────────────────────
          const SectionHeader('About'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(AppConfig.appName),
            subtitle: const Text('Credits, music providers and open-source licences'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConfig.appName,
              applicationLegalese:
                  'Music is streamed from third-party providers under their own terms. '
                  'Artists and rights holders retain all rights to their works.',
            ),
          ),
          if (AppConfig.supportEmail.isNotEmpty)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.support_agent_rounded),
              title: const Text('Support'),
              subtitle: const Text(AppConfig.supportEmail),
            ),
        ],
      ),
    );
  }

  static String _describe(SourceInfo i) {
    final what = i.fullTracks
        ? 'Full tracks'
        : i.previews
            ? 'Song info & previews'
            : 'Song info';
    return '$what · ${i.attribution}';
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(k, style: context.text.bodyMedium)),
            Text(v, style: context.text.titleMedium?.copyWith(fontSize: 14)),
          ],
        ),
      );

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (s) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your privacy', style: s.text.titleLarge),
              const SizedBox(height: 12),
              const Text(
                '• No account is required and the app has no advertising or analytics SDKs.\n'
                '• Favourites, playlists, history and settings are stored only on this device.\n'
                '• Search terms are sent to the enabled music services (listed under Music sources) '
                'to find songs, and those services receive your IP address when you stream.\n'
                '• Your Premium entitlement is stored in the device’s secure storage. Purchases are '
                'processed by Apple, Google or our payment provider; we never see card details.\n'
                '• Playback diagnostics are computed locally and never uploaded.\n'
                '• “Delete all my data” erases everything stored by the app on this device.',
              ),
              if (AppConfig.privacyPolicyUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => openExternal(s, AppConfig.privacyPolicyUrl),
                  child: const Text('Read the full privacy policy'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
