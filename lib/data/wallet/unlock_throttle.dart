/// Backoff state for repeated wrong PIN attempts.
///
/// A 6-digit PIN is a small search space, and PBKDF2 only slows each guess
/// down — it does not cap how many guesses an attacker can make. Without a
/// penalty the lock screen happily re-prompts forever, which makes an offline
/// attack on the vault cheap enough to be worth trying.
///
/// The state is therefore persisted (see `WalletStorage.readThrottle`) so that
/// force-quitting and relaunching the app cannot be used to reset the counter.
class UnlockThrottle {
  const UnlockThrottle({this.failedAttempts = 0, this.lockedUntil});

  /// The neutral state: no failures recorded.
  static const UnlockThrottle none = UnlockThrottle();

  /// Waiting time imposed after each consecutive failure. The first few
  /// mistakes cost nothing so an honest fat-finger is not punished; from there
  /// the penalty escalates and caps at 15 minutes.
  static const List<Duration> backoff = <Duration>[
    Duration.zero,
    Duration.zero,
    Duration.zero,
    Duration(seconds: 15),
    Duration(seconds: 60),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// Consecutive failures since the last successful unlock or wallet change.
  final int failedAttempts;

  /// When the current penalty expires. `null` when no penalty is active.
  final DateTime? lockedUntil;

  /// How long the user still has to wait before the next attempt is accepted.
  Duration remainingLockoutAt(DateTime now) {
    final DateTime? until = lockedUntil;
    if (until == null) {
      return Duration.zero;
    }
    final Duration left = until.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// `true` while [remainingLockoutAt] is still positive.
  bool isThrottledAt(DateTime now) =>
      remainingLockoutAt(now) > Duration.zero;

  /// The penalty applied to the [attempts]-th consecutive failure (1-based).
  static Duration delayForAttempts(int attempts) {
    if (attempts <= 0) {
      return Duration.zero;
    }
    return backoff[(attempts - 1).clamp(0, backoff.length - 1)];
  }

  /// Advances the counter after a rejected PIN.
  ///
  /// Returns the new state; callers persist it so the penalty survives a
  /// restart. A failure that carries no penalty still bumps [failedAttempts],
  /// which is what escalates the next one.
  UnlockThrottle recordFailure(DateTime now) {
    final int attempts = failedAttempts + 1;
    final Duration delay = delayForAttempts(attempts);
    return UnlockThrottle(
      failedAttempts: attempts,
      lockedUntil: delay == Duration.zero ? null : now.add(delay),
    );
  }

  /// The state to keep after a successful unlock.
  UnlockThrottle cleared() => none;

  /// Human-readable wait, e.g. `Try again in 15s` or `Try again in 5 min 00s`.
  String retryHint(DateTime now) {
    final Duration left = remainingLockoutAt(now);
    if (left <= Duration.zero) {
      return 'Try again now';
    }
    // Round up so a sub-second remainder still reads as "1s", never "0s".
    final int seconds = (left.inMilliseconds / 1000).ceil();
    if (seconds < 60) {
      return 'Try again in ${seconds}s';
    }
    final int minutes = seconds ~/ 60;
    final int rest = seconds % 60;
    return 'Try again in $minutes min ${rest.toString().padLeft(2, '0')}s';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'failedAttempts': failedAttempts,
        'lockedUntil': lockedUntil?.toIso8601String(),
      };

  /// Rebuilds a persisted throttle, tolerating missing or corrupt values.
  ///
  /// A malformed [lockedUntil] degrades to "no active penalty" rather than
  /// locking the user out of their own wallet; a negative attempt count is
  /// clamped to zero.
  factory UnlockThrottle.fromJson(Map<String, Object?>? json) {
    if (json == null) {
      return none;
    }
    final Object? attempts = json['failedAttempts'];
    final int count = attempts is num && attempts > 0 ? attempts.toInt() : 0;
    final Object? raw = json['lockedUntil'];
    final DateTime? until =
        raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    return UnlockThrottle(failedAttempts: count, lockedUntil: until);
  }

  @override
  String toString() =>
      'UnlockThrottle(attempts: $failedAttempts, until: $lockedUntil)';
}