import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/pages/admin/admin_access_lock.dart';
import 'package:mycosix/state/auth_controller.dart';

/// Authorization decision the admin gate makes. Pure function - no Firebase,
/// so the whole admin/not-admin/sign-in matrix is covered deterministically.
void main() {
  AdminGateStatus decide({
    bool backendAvailable = true,
    bool resolving = false,
    bool signedIn = false,
    bool? isAdmin,
  }) {
    return resolveAdminGate(
      backendAvailable: backendAvailable,
      resolving: resolving,
      signedIn: signedIn,
      isAdmin: isAdmin,
    );
  }

  // The owner phrase is intentionally never stored as a literal anywhere in
  // the repository; the code points are the source of truth.
  final secret = String.fromCharCodes(AdminAccessLock.secretCodePoints);

  group('AdminAccessLock', () {
    test('the owner phrase is matched code-point by code-point', () {
      expect(AdminAccessLock.matchesCode(secret), isTrue);
      expect(AdminAccessLock.matchesCode('  $secret  '), isTrue);
    });

    test('any other text is rejected', () {
      expect(AdminAccessLock.matchesCode(''), isFalse);
      expect(AdminAccessLock.matchesCode('nope'), isFalse);
      expect(AdminAccessLock.matchesCode('$secret-x'), isFalse);
      expect(AdminAccessLock.matchesCode(secret.toUpperCase()), isFalse);
    });

    test('one character changed is rejected', () {
      final wrong =
          secret.replaceFirst(secret[0], String.fromCharCode(secret.codeUnitAt(0) + 1));
      expect(wrong.length, secret.length);
      expect(AdminAccessLock.matchesCode(wrong), isFalse);
    });

    test('the phrase length is stable (window/field contract)', () {
      expect(AdminAccessLock.secretCodePoints.length, 12);
    });
  });

  group('resolveAdminGate', () {
    test('offline backend always wins, even for a signed-in admin', () {
      expect(
        decide(backendAvailable: false, signedIn: true, isAdmin: true),
        AdminGateStatus.backendOffline,
      );
      expect(
        decide(backendAvailable: false, resolving: true),
        AdminGateStatus.backendOffline,
      );
    });

    test('while loading (auth unsettled) shows the loading state', () {
      expect(decide(resolving: true), AdminGateStatus.resolving);
    });

    test('signed-in user waits (loading) until the grant is known', () {
      expect(decide(signedIn: true, isAdmin: null), AdminGateStatus.resolving);
    });

    test(
      'signed-out visitor goes to sign-in even before the grant is known',
      () {
        expect(decide(isAdmin: null), AdminGateStatus.signInRequired);
      },
    );

    test('signed-out visitor is asked to sign in', () {
      expect(decide(isAdmin: false), AdminGateStatus.signInRequired);
      expect(decide(isAdmin: true), AdminGateStatus.signInRequired);
    });

    test('signed-in account without an admins grant is not authorized', () {
      expect(decide(signedIn: true, isAdmin: false), AdminGateStatus.notAdmin);
    });

    test('signed-in account with a grant reaches the dashboard', () {
      expect(decide(signedIn: true, isAdmin: true), AdminGateStatus.admin);
    });
  });
}
