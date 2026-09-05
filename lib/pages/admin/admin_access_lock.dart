/// The owner summon phrase in front of the admin sign-in.
///
/// The real authorization is Firebase Auth plus the `admins/{uid}` grant. The
/// phrase is only obscurity in front of that boundary - typed exactly into the
/// Shop search box it summons the admin sign-in page instead of filtering
/// products. It is never a security boundary on its own.
///
/// The owner phrase is stored as a list of Unicode code points so it never
/// appears as a readable literal in the source or in the shipped bundle.
class AdminAccessLock {
  AdminAccessLock._();

  /// The owner phrase, as Unicode code points (length must stay 12).
  ///
  /// To change it, replace this list with the code points of the new phrase -
  /// e.g. from `String.fromCharCodes(newPhrase.codeUnits)` - and keep the same
  /// length. Do not write the phrase itself anywhere in this repository.
  static const List<int> secretCodePoints = <int>[
    77,
    121,
    67,
    111,
    83,
    105,
    120,
    65,
    100,
    109,
    105,
    110,
  ];

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
}
