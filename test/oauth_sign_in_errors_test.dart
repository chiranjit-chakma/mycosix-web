import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/state/customer_auth_controller.dart';

/// The friendly, human-safe wording for Twitter/X and Yahoo sign-in failures
/// - the shared Google core naming each provider, including the honest "not
/// switched on yet" state before the owner enables that provider once in the
/// Firebase console.
void main() {
  test('twitter operation-not-allowed names Twitter and the console switch',
      () {
    final m = friendlyTwitterSignInError(
      FirebaseAuthException(code: 'operation-not-allowed'),
    );
    expect(m, contains('Twitter'));
    expect(m, contains('Firebase console'));
    expect(m, contains('email + password'));
    expect(m,
        isNot(contains('operation-not-allowed')),
        reason: 'no raw error codes');
  });

  test('yahoo operation-not-allowed names Yahoo and the console switch', () {
    final m = friendlyYahooSignInError(
      FirebaseAuthException(code: 'operation-not-allowed'),
    );
    expect(m, contains('Yahoo'));
    expect(m, contains('Firebase console'));
    expect(m, contains('email + password'));
    expect(m, isNot(contains('operation-not-allowed')));
  });

  test('a closed twitter popup reads as a closed popup', () {
    final m = friendlyTwitterSignInError(
      FirebaseAuthException(code: 'popup-closed-by-user'),
    );
    expect(m, contains('Twitter'));
    expect(m, contains('closed'));
  });

  test('a blocked yahoo popup suggests allowing pop-ups', () {
    final m = friendlyYahooSignInError(
      FirebaseAuthException(code: 'popup-blocked'),
    );
    expect(m, contains('Yahoo'));
    expect(m, contains('pop-ups'));
  });

  test('account-exists-with-different-credential points at password sign-in',
      () {
    final m = friendlyYahooSignInError(
      FirebaseAuthException(code: 'account-exists-with-different-credential'),
    );
    expect(m, contains('password'));
  });

  test('google messages still name Google after the shared-core refactor', () {
    final m = friendlyGoogleSignInError(
      FirebaseAuthException(code: 'operation-not-allowed'),
    );
    expect(m, contains('Google'));
  });

  test('unknown twitter auth errors fall back to the shared friendly message',
      () {
    final m = friendlyTwitterSignInError(
      FirebaseAuthException(code: 'unrecognised-code'),
    );
    expect(m, isNotEmpty);
    expect(m, isNot(contains('Twitter')), reason: 'no provider internals');
  });

  test('non-auth errors fall back safely too', () {
    final m = friendlyYahooSignInError(Exception('boom'));
    expect(m, isNotEmpty);
  });
}
