import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/player_controller.dart';
import '../controllers/player_controller_state.dart';
import 'source_providers.dart';

final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlayerControllerState>((ref) {
  return PlayerController(
    aggregator: ref.watch(searchAggregatorProvider),
    sourceById: (id) => ref.read(sourceByIdProvider(id)),
  );
});

/// Becomes `true` while any modal bottom sheet is open.
/// MiniPlayer watches this provider and hides itself whenever a sheet is active,
/// preventing it from overlapping sheet content.
final bottomSheetActiveProvider = StateProvider<bool>((ref) => false);
