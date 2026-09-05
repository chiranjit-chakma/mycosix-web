import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

/// A lightweight access-code door in front of the admin sign-in.
///
/// The real authorization is Firebase Auth plus the `admins/{uid}` grant. The
/// door only keeps the sign-in page out of plain sight: a customer who wanders
/// to /admin sees a locked prompt, and the sign-in form appears only after the
/// code is entered. It is deliberately client-side obscurity, never a security
/// boundary - the code is compiled into the app bundle - so do not treat it as
/// protection on its own.
class AdminAccessLock {
  AdminAccessLock();

  /// The shared instance used by the routed admin gate.
  static final AdminAccessLock shared = AdminAccessLock();

  /// Change this to any phrase you like. Because it ships in the bundle it is
  /// only a "staff only" sign, not a lock.
  static const String accessCode = 'mxgrowsecret';

  final ValueNotifier<bool> _unlocked = ValueNotifier<bool>(false);

  /// Door state, for [ValueListenableBuilder].
  ValueListenable<bool> get unlocked => _unlocked;

  bool get isUnlocked => _unlocked.value;

  /// Opens the door when [candidate] matches [accessCode].
  bool tryUnlock(String candidate) {
    if (candidate.trim() == accessCode) {
      if (!_unlocked.value) _unlocked.value = true;
      return true;
    }
    return false;
  }
}
