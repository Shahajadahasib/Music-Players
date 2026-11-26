/// Per-provider health with a simple circuit breaker.
///
/// After [failureThreshold] consecutive failures (timeouts, network or server
/// errors) a provider is paused for [cooldown], so a provider that is down
/// doesn't slow every search by its full timeout. The first request after
/// the cooldown is a trial: success closes the circuit, failure re-opens it.
class ProviderHealth {
  ProviderHealth({
    this.failureThreshold = 3,
    this.cooldown = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int failureThreshold;
  final Duration cooldown;
  final DateTime Function() _clock;

  final Map<String, ProviderStatus> _status = {};

  ProviderStatus statusOf(String id) => _status[id] ?? const ProviderStatus();

  /// Snapshot for diagnostics (Settings).
  Map<String, ProviderStatus> get all => Map.unmodifiable(_status);

  bool isPaused(String id) {
    final s = _status[id];
    if (s == null || s.pausedUntil == null) return false;
    return _clock().isBefore(s.pausedUntil!);
  }

  void recordSuccess(String id) {
    final s = statusOf(id);
    _status[id] = ProviderStatus(
      successes: s.successes + 1,
      failures: s.failures,
      lastError: s.lastError,
    );
  }

  void recordFailure(String id, String error) {
    final s = statusOf(id);
    final consecutive = s.consecutiveFailures + 1;
    _status[id] = ProviderStatus(
      successes: s.successes,
      failures: s.failures + 1,
      consecutiveFailures: consecutive,
      lastError: error,
      pausedUntil: consecutive >= failureThreshold ? _clock().add(cooldown) : null,
    );
  }
}

class ProviderStatus {
  const ProviderStatus({
    this.successes = 0,
    this.failures = 0,
    this.consecutiveFailures = 0,
    this.lastError = '',
    this.pausedUntil,
  });

  final int successes;
  final int failures;
  final int consecutiveFailures;
  final String lastError;
  final DateTime? pausedUntil;
}
