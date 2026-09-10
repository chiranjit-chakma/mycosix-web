/// Pure logic for taking an administrator's access back. Kept free of Firebase
/// so it is unit-testable like the rest of the pure logic in this app.
library;

import 'admin_emails.dart';

/// The two ways an admin grant ends: an admin leaves the team, or another
/// admin takes their access back. Both are the same removal underneath, so
/// both go through the rules and the checks here.
class AdminTeam {
  AdminTeam._();

  /// Why the grant for this person must not be removed right now, or null when
  /// the removal is allowed.
  ///
  /// There is exactly one refusal: this is the last administrator. Firestore
  /// rules cannot count a collection, so the guard cannot live there - it lives
  /// here, and the admin area shows this sentence instead of removing. Without
  /// it a lone admin could give up their own grant and leave MYCOSIX with
  /// nobody who can manage the shop, recoverable only from the Firebase
  /// console.
  ///
  /// [isSelf] is true when the admin being removed is the one asking, which
  /// only changes the wording ([adminCount] of 1 always means "you").
  static String? removalBlockedReason({
    required bool isSelf,
    required int adminCount,
  }) {
    if (adminCount > 1) return null;
    return isSelf
        ? 'You are the only administrator, so your own access cannot be '
            'removed - that would leave nobody able to run the shop. Add '
            'another administrator first, then you can leave.'
        : 'This is the only administrator account, so it cannot be removed - '
            'that would leave nobody able to run the shop.';
  }

  /// The `adminCodes/{email}` document that belongs to a grant carrying
  /// [emailOnGrant], or null when the grant holds no usable email (a legacy
  /// grant from before per-email codes existed).
  ///
  /// Removing a grant is only half the job: while this row survives, the
  /// removed person could type their code again and walk straight back in, so a
  /// removal deletes this row first and only then the grant.
  static String? codeDocIdFor(String? emailOnGrant) {
    final raw = (emailOnGrant ?? '').trim();
    if (!isPlausibleAdminEmail(raw)) return null;
    return adminEmailKey(raw);
  }
}
