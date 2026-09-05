import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

/// The hidden access-code door in front of the admin sign-in.
///
/// The real authorization is Firebase Auth plus the `admins/{uid}` grant. The
/// door, the wordmark long-press and the typed phrase only keep the admin area
/// out of plain sight — none of them is ever a security boundary on its own,
/// so they are layered *in front of* the real sign-in, never instead of it.
///
/// The owner phrase is stored as a list of Unicode code points so it never
/// appears as a readable literal in the source or in the shipped bundle.
class AdminAccessLock {
  AdminAccessLock();

  /// The shared instance used by the routed admin gate.
  static final AdminAccessLock shared = AdminAccessLock();

  /// The owner phrase, as Unicode code points (length must stay 12).
  ///
  /// To change it, replace this list with the code points of the new phrase —
  /// e.g. from `String.fromCharCodes(newPhrase.codeUnits)` — and keep the
  /// same length. Do not write the phrase itself anywhere in this repository.
  static const List<int> secretCodePoints = <int>[
    109,
    120,
    103,
    114,
    111,
    119,
    115,
    101,
    99,
    114,
    101,
    116,
  ];

  /// Number of characters in the owner phrase (window size for the typed
  /// phrase listener in `state/admin_reveal.dart`).
  static int get secretLength => secretCodePoints.length;

  /// True when [candidate] (ignoring surrounding whitespace) equals the owner
  /// phrase, compared code-point by code-point so no string literal exists.
  static bool matchesCode(String candidate) {
    final trimmed = candidate.trim();
    if (trimmed.length != secretCodePoints.length) return false;
    for (var i = 0; i < trimmed.length; i++) {
      if (trimmed.codeUnitAt(i) != secretCodePoints[i]) return false;
    }
    return true;
  }

  final ValueNotifier<bool> _unlocked = ValueNotifier<bool>(false);

  /// Door state, for [ValueListenableBuilder].
  ValueListenable<bool> get unlocked => _unlocked;

  bool get isUnlocked => _unlocked.value;

  /// Opens the door when [candidate] matches the owner phrase.
  bool tryUnlock(String candidate) {
    if (matchesCode(candidate)) {
      if (!_unlocked.value) _unlocked.value = true;
      return true;
    }
    return false;
  }
}
