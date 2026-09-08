import 'package:firebase_auth/firebase_auth.dart';

import '../firebase/fb.dart';

/// Kinds of failure a verification step can hit, so the UI can react with the
/// right copy and the right next action instead of guessing from text.
enum OtpFailure {
  /// The 6-digit code was wrong.
  wrongCode,

  /// The code (or its request) is no longer valid - a new one is needed.
  expired,

  /// The provider or Firebase is rate-limiting this number/browser.
  limited,

  /// No backend reachable.
  offline,

  /// Phone (SMS) sign-in is not switched on for this Firebase project.
  notEnabled,

  /// The number is already linked to a different MYCOSIX account.
  onAnotherAccount,

  /// Anything else.
  other,
}

/// Result of asking the SMS provider to send a one-time code: either the
/// opaque verification handle needed to confirm it, or a customer-safe error.
/// The handle is only ever held in memory for the current step - never
/// displayed, persisted or logged.
class OtpRequest {
  const OtpRequest._(this.verificationId, this.failure, this.message);

  const OtpRequest.ready(String verificationId)
      : this._(verificationId, null, null);

  const OtpRequest.failed(OtpFailure failure, String message)
      : this._(null, failure, message);

  /// Opaque handle for [WhatsAppOtpService.verifyCode].
  final String? verificationId;

  final OtpFailure? failure;

  /// Customer-safe copy shown next to the field.
  final String? message;

  bool get ok => verificationId != null;
}

/// Result of entering the code.
class OtpVerification {
  const OtpVerification._(this.verified, this.freshSession, this.failure, this.message);

  const OtpVerification.ok({required bool freshSession})
      : this._(true, freshSession, null, null);

  const OtpVerification.failed(OtpFailure failure, String message)
      : this._(false, false, failure, message);

  final bool verified;
  final OtpFailure? failure;

  /// Customer-safe copy shown next to the field.
  final String? message;

  /// True only when a brand-new sign-in session was created to prove the
  /// number (guest checkout, or an account whose session was replaced by the
  /// guest number). The checkout signs that session out again once the order
  /// is placed, so no throwaway account is left signed in on the device.
  final bool freshSession;
}

/// The WhatsApp-number verification the checkout runs before an order may be
/// placed: a one-time code sent by SMS via Firebase Phone Auth (the project's
/// configured provider) and confirmed against the same service.
///
/// Security contract:
///  - the code is entered by the customer and sent straight to Firebase; it is
///    never stored, printed, logged or shipped to any server of ours,
///  - no client-side "verified" flag is ever trusted: the Firestore rules (and
///    the trusted order function) pin every recorded order's phone to the
///    phone number on the caller's own Firebase auth token, which only exists
///    after Firebase itself verified the code,
///  - the service only ever attests "the session now carries this exact
///    number", and it decides that from Firebase's own current user, never
///    from a value the browser could have set.
class WhatsAppOtpService {
  const WhatsAppOtpService();

  /// Sends a one-time code by SMS to [canonicalPhone] (already canonical
  /// '+91XXXXXXXXXX'). Returns the verification handle when the SMS is away.
  Future<OtpRequest> requestCode(String canonicalPhone) async {
    if (!Fb.enabled) return _offline();
    try {
      // No RecaptchaVerifier is passed: Firebase auto-creates an invisible
      // reCAPTCHA for this page when the provider is enabled.
      final result = await Fb.auth.signInWithPhoneNumber(canonicalPhone);
      return OtpRequest.ready(result.verificationId);
    } on FirebaseAuthException catch (e) {
      return OtpRequest.failed(_sendFailure(e), _sendMessage(e));
    } catch (_) {
      return const OtpRequest.failed(
        OtpFailure.other,
        'We could not send the verification code right now. Please try again.',
      );
    }
  }

  /// Confirms the SMS [code] for the number [canonicalPhone].
  ///
  /// How the proof is attached depends on the session at confirm time:
  ///  - nobody signed in: a fresh phone sign-in session is created
  ///    ([OtpVerification.freshSession] is true),
  ///  - a signed-in account WITHOUT a phone: the number is linked to that
  ///    account, so their next checkout skips this step entirely,
  ///  - a signed-in account WITH a different phone: the phone credential
  ///    replaces the session (the verify panel discloses this before the
  ///    customer confirms, because their previous sign-in ends).
  Future<OtpVerification> verifyCode({
    required String verificationId,
    required String code,
    required String canonicalPhone,
  }) async {
    if (!Fb.enabled) return _verifyFailed(OtpFailure.offline, '');
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code.trim(),
      );
      final user = Fb.auth.currentUser;

      // Nobody signed in (or the session was already dropped): the verified
      // number becomes its own short-lived session.
      if (user == null) {
        await Fb.auth.signInWithCredential(credential);
        return const OtpVerification.ok(freshSession: true);
      }

      // The session already carries exactly this number - Firebase verified it
      // when it was linked, so there is nothing more to prove. (Can only
      // happen through a race between sending and confirming.)
      if (user.phoneNumber == canonicalPhone) {
        return const OtpVerification.ok(freshSession: false);
      }

      // A signed-in account with a DIFFERENT verified phone: signing in with
      // this credential replaces the session (disclosed in the panel). No
      // explicit sign-out is needed - Firebase swaps the session on confirm.
      if (user.phoneNumber != null) {
        await Fb.auth.signInWithCredential(credential);
        return const OtpVerification.ok(freshSession: true);
      }

      // A real account without a phone yet: attach the number to the account
      // so the next order on this number needs no code at all.
      await user.linkWithCredential(credential);
      // Force a fresh ID token so the phone_number claim reaches the rules.
      await Fb.auth.currentUser?.getIdToken(true);
      return const OtpVerification.ok(freshSession: false);
    } on FirebaseAuthException catch (e) {
      // The number is already attached to another account. Check whether the
      // link actually landed (a retry race), otherwise tell the customer.
      if (e.code == 'provider-already-linked' ||
          e.code == 'credential-already-in-use') {
        final now = Fb.auth.currentUser;
        if (now != null && now.phoneNumber == canonicalPhone) {
          return const OtpVerification.ok(freshSession: false);
        }
        return _verifyFailed(
          OtpFailure.onAnotherAccount,
          'This number is already linked to another MYCOSIX account. Please '
              'sign in with that account, or use a different number.',
        );
      }
      return _verifyFailed(_verifyFailure(e), _verifyMessage(e));
    } catch (_) {
      return const OtpVerification.failed(
        OtpFailure.other,
        'The code could not be verified. Please try again.',
      );
    }
  }

  static OtpRequest _offline() => const OtpRequest.failed(
        OtpFailure.offline,
        'We could not reach the verification service right now. Please check '
            'your connection and try again.',
      );

  static OtpVerification _verifyFailed(OtpFailure f, String m) =>
      OtpVerification.failed(f, m.isEmpty ? _fallback(m) : m);

  static String _fallback(String m) =>
      'The code could not be verified. Please try again.';

  static OtpFailure _sendFailure(FirebaseAuthException e) {
    switch (e.code) {
      case 'operation-not-allowed':
      case 'admin-restricted-operation':
        return OtpFailure.notEnabled;
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return OtpFailure.other;
      case 'too-many-requests':
        return OtpFailure.limited;
      case 'network-request-failed':
        return OtpFailure.offline;
      case 'quota-exceeded':
        return OtpFailure.limited;
      case 'captcha-check-failed':
        return OtpFailure.other;
      default:
        return OtpFailure.other;
    }
  }

  static String _sendMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'operation-not-allowed':
      case 'admin-restricted-operation':
        return 'We cannot send verification codes right now. Please try '
            'again shortly, or message us on WhatsApp - no order has been '
            'placed.';
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return 'That number could not be verified. Please check it and try '
            'again.';
      case 'too-many-requests':
        return 'Too many codes have been sent to this number. Please wait a '
            'few minutes and try again.';
      case 'quota-exceeded':
        return 'We have reached our SMS limit for the moment. Please try '
            'again shortly.';
      case 'network-request-failed':
        return 'No internet connection - please check and try again.';
      case 'captcha-check-failed':
        return 'The safety check did not complete. Please try again.';
      default:
        return 'We could not send the verification code right now. Please '
            'try again.';
    }
  }

  static OtpFailure _verifyFailure(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
      case 'mismatching-verification-code':
        return OtpFailure.wrongCode;
      case 'invalid-verification-id':
      case 'expired-action-code':
      case 'session-expired':
        return OtpFailure.expired;
      case 'too-many-requests':
      case 'quota-exceeded':
        return OtpFailure.limited;
      case 'network-request-failed':
        return OtpFailure.offline;
      case 'credential-already-in-use':
        return OtpFailure.onAnotherAccount;
      default:
        return OtpFailure.other;
    }
  }

  static String _verifyMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
      case 'mismatching-verification-code':
        return 'That code is not right. Please check the SMS and try again.';
      case 'invalid-verification-id':
      case 'expired-action-code':
      case 'session-expired':
        return 'That code has expired. Please request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'quota-exceeded':
        return 'We have reached our SMS limit for the moment. Please try '
            'again shortly.';
      case 'network-request-failed':
        return 'No internet connection - please check and try again.';
      default:
        return 'The code could not be verified. Please try again.';
    }
  }
}
