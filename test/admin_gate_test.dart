import 'package:flutter_test/flutter_test.dart';
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
