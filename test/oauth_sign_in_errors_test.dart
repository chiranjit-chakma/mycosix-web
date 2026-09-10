import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/state/customer_auth_controller.dart';

/// The friendly, human-safe wording for a Google sign-in failure: a short
/// message naming Google, including the honest "not switched on yet" state
/// before the owner enables the provider once in the Firebase console.
///
/// Google is the only social provider. Twitter and Yahoo were removed from
/// the app entirely - they were never switched on for this project, so their
/// buttons could only ever have failed - and their wording went with them.
void main() {
  test('operation-not-allowed names Google and the console switch', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'operation-not-allowed'),
    );
    expect(m, contains('Google'));
    expect(m, contains('Firebase console'));
    expect(m, contains('email + password'));
    expect(
      m,
      isNot(contains('operation-not-allowed')),
      reason: 'no raw error codes',
    );
  });

  test('a closed Google popup reads as a closed popup', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'popup-closed-by-user'),
    );
    expect(m, contains('Google'));
    expect(m, contains('closed'));
  });

  test('a blocked Google popup suggests allowing pop-ups', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'popup-blocked'),
    );
    expect(m, contains('Google'));
    expect(m, contains('pop-ups'));
  });

  test('account-exists-with-different-credential points at password sign-in',
      () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'account-exists-with-different-credential'),
    );
    expect(m, contains('password'));
  });

  test('an unauthorized domain names Google and the console setting', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'unauthorized-domain'),
    );
    expect(m, contains('Google'));
    expect(m, contains('Authorized domains'));
  });

  test('a cancelled Google window reads as cancelled', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'redirect-cancelled-by-user'),
    );
    expect(m, contains('Google'));
    expect(m, contains('cancelled'));
  });

  test('unknown auth errors fall back to the shared friendly message', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'unrecognised-code'),
    );
    expect(m, isNotEmpty);
    expect(m, isNot(contains('Google')), reason: 'no provider internals');
  });

  test('non-auth errors fall back safely too', () {
    final m = friendlyGoogleSignInError(Exception('boom'));
    expect(m, isNotEmpty);
  });
}
