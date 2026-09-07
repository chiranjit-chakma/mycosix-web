import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/state/customer_auth_controller.dart';

/// The friendly, human-safe wording for Google sign-in failures - including
/// the honest "not switched on yet" state before the owner enables Google in
/// the Firebase console.
void main() {
  test('operation-not-allowed explains the one-time console switch', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'operation-not-allowed'),
    );
    expect(m, contains('Firebase console'));
    expect(m, contains('email + password'));
    expect(m, isNot(contains('operation-not-allowed')), reason: 'no raw error codes');
  });

  test('a closed popup reads as a closed popup', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'popup-closed-by-user'),
    );
    expect(m, contains('closed'));
  });

  test('a blocked popup suggests allowing pop-ups', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'popup-blocked'),
    );
    expect(m, contains('pop-ups'));
  });

  test('account-exists-with-different-credential points at password sign-in',
      () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'account-exists-with-different-credential'),
    );
    expect(m, contains('password'));
  });

  test('unknown auth errors fall back to the shared friendly message', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'unrecognised-code'),
    );
    expect(m, isNotEmpty);
    expect(m, isNot(contains('Firebase')), reason: 'no provider internals');
  });

  test('non-auth errors fall back safely too', () {
    final m = friendlyGoogleSignInError(Exception('boom'));
    expect(m, isNotEmpty);
  });
}
