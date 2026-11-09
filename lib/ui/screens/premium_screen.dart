import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../licensing/license_controller.dart';
import '../../theme/aurora_theme.dart';
import '../navigation.dart';

/// One-time purchase / licence management.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  final _keyController = TextEditingController();
  bool _activating = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  static const _features = [
    (Icons.queue_music_rounded, 'Unlimited playlists', 'Free plan: ${AppConfig.freePlaylistLimit} playlists'),
    (Icons.phone_iphone_rounded, 'Play your own music files', 'MP3, AAC, M4A, WAV, FLAC from your device'),
    (Icons.bedtime_rounded, 'Sleep timer', 'Fade off to sleep on your schedule'),
    (Icons.palette_rounded, 'Light & system themes', 'Match your device’s appearance'),
    (Icons.favorite_rounded, 'Support independent development', 'Pay once, keep it forever — no subscription'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(licenseControllerProvider);
    final c = ref.read(licenseControllerProvider.notifier);
    final p = context.palette;

    ref.listen(licenseControllerProvider.select((s) => s.message), (_, msg) {
      if (msg == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      c.clearMessage();
    });

    final price = s.product?.price;
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(gradient: p.brandGradient, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text(
                  s.isPremium ? 'You’re Premium' : '${AppConfig.appName} Premium',
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  s.isPremium
                      ? 'Unlocked via ${switch (s.source) { 'store' => 'your store purchase', 'key' => 'licence key', _ => 'your purchase' }}.'
                      : 'A single payment unlocks everything, forever.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final f in _features)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(f.$1, color: p.accent),
              title: Text(f.$2),
              subtitle: Text(f.$3),
              trailing: s.isPremium ? Icon(Icons.check_circle_rounded, color: p.success) : null,
            ),
          const SizedBox(height: 12),
          if (s.tier == LicenseTier.checking)
            const Center(child: CircularProgressIndicator())
          else if (!s.isPremium) ...[
            if (s.storeAvailable) ...[
              FilledButton(
                onPressed: s.purchasePending ? null : c.buy,
                child: Text(s.purchasePending
                    ? 'Waiting for the store…'
                    : price == null
                        ? 'Buy Premium'
                        : 'Buy Premium · $price one-time'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: c.restore, child: const Text('Restore purchase')),
            ] else if (kIsWeb && AppConfig.webCheckoutUrl.isNotEmpty) ...[
              FilledButton(
                onPressed: () => openExternal(context, AppConfig.webCheckoutUrl),
                child: const Text('Buy a licence key'),
              ),
              const SizedBox(height: 4),
              Text('After payment you’ll receive a licence key to paste below.',
                  style: context.text.bodySmall, textAlign: TextAlign.center),
            ] else
              Text(
                'Purchases aren’t available on this device. If you bought a licence key, enter it below.',
                style: context.text.bodyMedium,
              ),
            const SizedBox(height: 24),
            Text('Have a licence key?', style: context.text.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _keyController,
              minLines: 1,
              maxLines: 3,
              maxLength: 2048,
              decoration: const InputDecoration(hintText: 'AURORA1.…', counterText: ''),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _activating
                  ? null
                  : () async {
                      setState(() => _activating = true);
                      await c.activateKey(_keyController.text);
                      if (mounted) setState(() => _activating = false);
                    },
              child: Text(_activating ? 'Checking…' : 'Activate'),
            ),
          ] else if (s.source != 'paid-app') ...[
            if (s.storeAvailable)
              OutlinedButton(onPressed: c.restore, child: const Text('Restore purchase on this device')),
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Remove licence from this device?'),
                    content: const Text('You can restore it later with “Restore purchase” or your licence key.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
                    ],
                  ),
                );
                if (ok == true) await c.deactivate();
              },
              child: const Text('Remove licence from this device'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Premium is a one-time purchase of app features. It does not buy rights to any music: '
            'all streaming is provided free by the listed music services under their own terms, and '
            'catalogue availability can change.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}
