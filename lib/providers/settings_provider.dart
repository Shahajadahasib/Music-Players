import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hive_storage_service.dart';

class AppSettings extends Equatable {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.disabledSources = const {},
  });

  final ThemeMode themeMode;
  final Set<String> disabledSources;

  AppSettings copyWith({
    ThemeMode? themeMode,
    Set<String>? disabledSources,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        disabledSources: disabledSources ?? this.disabledSources,
      );

  @override
  List<Object?> get props => [themeMode, disabledSources];
}

/// Persistent user settings (Hive `settings_box`).
class SettingsController extends StateNotifier<AppSettings> {
  SettingsController() : super(_load());

  static const _kTheme = 'themeMode';
  static const _kDisabled = 'disabledSources';

  static AppSettings _load() {
    try {
      final theme = HiveStorageService.readSetting<String>(_kTheme);
      final disabled = HiveStorageService.readSetting<List>(_kDisabled);
      return AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == theme,
          orElse: () => ThemeMode.dark,
        ),
        disabledSources: {...?disabled?.whereType<String>()},
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await HiveStorageService.writeSetting(_kTheme, mode.name);
  }

  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final next = {...state.disabledSources};
    enabled ? next.remove(sourceId) : next.add(sourceId);
    state = state.copyWith(disabledSources: next);
    await HiveStorageService.writeSetting(_kDisabled, next.toList());
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) => SettingsController());
