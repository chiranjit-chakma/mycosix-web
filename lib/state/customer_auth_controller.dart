import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/fb.dart';
import '../services/display_mode.dart';
import 'cart_sync_controller.dart';

/// How an attempt to close a customer account ended.
enum AccountDeletionOutcome {
  /// The sign-in and every record this account owned are gone.
  deleted,

  /// The customer did not prove it is really them, so nothing was touched.
  /// [CustomerAuthController.message] says why (a wrong password, a closed
  /// Google window, and so on).
  notConfirmed,

  /// Proof was accepted but a step failed part-way. The account may still
  /// exist; the message says what happened, and the customer can try again
  /// or sign out and ask for help.
  failed,
}

/// The proof a customer offers that they really are the account holder, which
/// Firebase demands before it will delete a sign-in. An account created with
/// an email + password confirms with that password; an account created with
/// Google has no password to give, so it confirms with Google.
class AccountProof {
  const AccountProof.password(this.password) : google = false;

  const AccountProof.google() : password = null, google = true;

  final String? password;
  final bool google;
}

/// Where a visitor stands on the customer-account ladder.
enum CustomerAuthStatus {
  /// Firebase is not initialised (offline / not configured). There is nothing
  /// to sign in to, and the profile page says so instead of faking accounts.
  backendOffline,

  /// Auth state still loading.
  resolving,

  /// No signed-in customer: show the sign-in / create-account forms.
  signedOut,

  /// A real, provider-backed session exists.
  signedIn,
}

/// Pure decision used by the profile page. Kept free of Firebase so it can be
/// unit-tested without a live backend. Ordering matters: an offline backend
/// always wins, then loading, then the signed-in check.
CustomerAuthStatus resolveCustomerAuthStatus({
  required bool backendAvailable,
  required bool resolving,
  required bool signedIn,
}) {
  if (!backendAvailable) return CustomerAuthStatus.backendOffline;
  if (resolving) return CustomerAuthStatus.resolving;
  if (!signedIn) return CustomerAuthStatus.signedOut;
  return CustomerAuthStatus.signedIn;
}

/// Maps a Google sign-in failure to a short, human-safe message. Kept free of
/// Firebase state so it can be unit-tested without a live backend. The
/// "operation-not-allowed" case is expected until the owner enables the
/// Google sign-in method once in the Firebase console.
String friendlyGoogleSignInError(Object error) =>
    friendlyOAuthSignInError(error, method: 'Google');

/// The friendly mappers behind Google sign-in: a short, human-safe message
/// naming the provider. The "operation-not-allowed" case is expected until the
/// owner enables that provider once in the Firebase console; anything
/// unrecognised falls back to [Fb.friendlyMessage].
String friendlyOAuthSignInError(Object error, {required String method}) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'operation-not-allowed':
        return '$method sign-in is not switched on for MYCOSIX yet - the '
            'owner needs to enable it once in the Firebase console. You can '
            'still sign in with email + password.';
      case 'popup-closed-by-user':
        return 'The $method window was closed before sign-in finished. '
            'Try again when you are ready.';
      case 'popup-blocked':
        return 'Your browser blocked the $method window. Allow pop-ups for '
            'this site and try again.';
      case 'account-exists-with-different-credential':
        return 'An account with this email already exists with a password. '
            'Sign in with your email + password instead.';
      case 'unauthorized-domain':
        return '$method sign-in is not allowed from this web address yet. '
            'The owner needs to add it in the Firebase console under '
            'Authentication > Settings > Authorized domains.';
      case 'web-storage-unsupported':
        return 'This browser is blocking the storage $method sign-in needs '
            "(Private/Incognito windows and 'block all cookies' both do "
            'this). Use a normal window, or allow cookies for this site.';
      case 'redirect-cancelled-by-user':
        return 'The $method sign-in window was cancelled. Try again when '
            'you are ready.';
      case 'cancelled-popup-request':
        return 'Another $method sign-in was already opening. Wait a moment '
            'and try again.';
      case 'invalid-credential':
      case 'user-not-found':
        return '$method could not confirm this account. Try again, or use '
            'email + password.';
      default:
        return Fb.friendlyMessage(error);
    }
  }
  return Fb.friendlyMessage(error);
}

/// Customer authentication state — registration, sign-in, sign-out, password
/// recovery and email verification, all through Firebase Auth's own secure
/// mechanisms.
///
/// The single source of truth for "who is signed in" is Firebase Auth. This
/// controller never stores passwords, never touches one-time codes, and never
/// fabricates a session: when the backend is unavailable it reports so.
///
/// Being a *customer* account grants nothing beyond customer features — admin
/// authorisation is a separate grant (`admins/{uid}`) checked server-side by
/// the Firestore rules, so a registered customer can never become an admin by
/// editing anything in the browser.
class CustomerAuthController extends ChangeNotifier implements CartSyncAuth {
  CustomerAuthController() {
    _start();
  }

  final bool _backendAvailable = Fb.enabled;
  bool get backendAvailable => _backendAvailable;

  bool _resolving = true;
  bool get resolving => _resolving;

  User? _user;
  User? get user => _user;

  // CartSyncAuth: the account the cart syncs for (null = guest).
  @override
  String? get uid => _user?.uid;

  String? get email => _user?.email;

  String? get displayName => _user?.displayName;

  /// The phone number Firebase has verified on this account ('+91...'),
  /// when the customer has linked one. Read at checkout: an order contact
  /// number the account already carries needs no new one-time code.
  String? get phoneNumber => _user?.phoneNumber;

  bool get emailVerified => _user?.emailVerified ?? false;

  /// Account creation time as reported by the provider, when known.
  DateTime? get memberSince {
    final raw = _user?.metadata.creationTime;
    if (raw == null || raw.millisecondsSinceEpoch == 0) return null;
    return raw;
  }

  /// Last customer-safe failure message (sign-in, registration, reset), or
  /// null. Never contains stack traces or provider internals.
  String? _message;
  String? get message => _message;

  /// Last positive confirmation ("reset email sent"), or null.
  String? _notice;
  String? get notice => _notice;

  /// True while a social sign-in is finishing through the full-page redirect
  /// flow (its popup was blocked on the web). The whole page is on its way to
  /// the provider; the auth-state listener completes the session when the
  /// browser returns, so nothing may touch the navigator in the meantime.
  bool _redirectInFlight = false;
  bool get redirectInFlight => _redirectInFlight;

  /// Clears the redirect flag once the caller has stood aside for it.
  void clearRedirectInFlight() => _redirectInFlight = false;

  StreamSubscription<User?>? _authSub;

  void _start() {
    if (!_backendAvailable) {
      _resolving = false;
      return;
    }
    // A Google sign-in that left through the full-page redirect is finished
    // here, before anything else reads the session.
    unawaited(_completePendingRedirect());
    _authSub = Fb.auth.authStateChanges().listen(
      (u) {
        _user = u;
        _resolving = false;
        notifyListeners();
        // Best-effort profile document (the admin Customers section reads
        // `customers/{uid}`). Idempotent, owner-scoped, and validated by the
        // Firestore rules; a failure here never blocks the real session.
        if (u != null) {
          unawaited(_ensureProfileDoc(u));
        }
      },
      onError: (Object e) {
        _resolving = false;
        notifyListeners();
      },
    );
  }

  /// Completes a Google sign-in that came back through the full-page redirect
  /// (used when the popup was blocked, and always in an installed app). Web
  /// only - there is no redirect round trip anywhere else - and a failure is
  /// reported on the page exactly like a popup failure would be. A launch with
  /// nothing pending is not an error, so it stays silent.
  Future<void> _completePendingRedirect() async {
    if (!kIsWeb || !_backendAvailable) return;
    try {
      await Fb.auth.getRedirectResult();
    } catch (e) {
      if (e is FirebaseAuthException &&
          (e.code == 'no-auth-event' || e.code == 'no-current-user')) {
        return;
      }
      _message = friendlyGoogleSignInError(e);
      notifyListeners();
    }
  }

  /// Creates the customer's own `customers/{uid}` document if it does not
  /// exist yet. The write is bounded by the rules: only the owner may create
  /// it, the email must match their verified provider email, and the status is
  /// pinned to 'active'.
  Future<void> _ensureProfileDoc(User u) async {
    try {
      final ref = Fb.customers.doc(u.uid);
      final snap = await ref.get();
      if (snap.exists) return;
      await ref.set({
        'email': u.email ?? '',
        if ((u.displayName ?? '').trim().isNotEmpty)
          'displayName': u.displayName!.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });
    } catch (e) {
      // Rules not deployed / offline: the session is still real; the profile
      // document is retried on the next sign-in. Reported, never faked.
      debugPrint('MYCOSIX: customer profile doc not written ($e)');
    }
  }

  /// Signs in an existing customer. Returns success; failures surface as a
  /// customer-safe message on [message].
  Future<bool> signIn({required String email, required String password}) async {
    if (!_backendAvailable) return false;
    _clearFeedback();
    notifyListeners();
    try {
      await Fb.auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return true;
    } catch (e) {
      _message = Fb.friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Signs the customer in with their Google account (a popup window). A first
  /// Google sign-in also creates the account. The Firestore rules treat the
  /// Google-verified email exactly like a password-account email, so no rules
  /// change is needed. Failures surface as a customer-safe message.
  Future<bool> signInWithGoogle() => _signInWithPopup(
    GoogleAuthProvider(),
    friendly: friendlyGoogleSignInError,
  );

  /// Shared body of the social popup sign-ins above: opens the provider's
  /// popup, hands the verified session to Firebase, and reports any failure
  /// as a customer-safe message. Returns success.
  ///
  /// The popup is not the only way in. In an INSTALLED app (a phone home-screen
  /// icon, where the window has no browser chrome to host a popup) the redirect
  /// is used from the start, and on a normal page any popup failure that means
  /// "the browser would not give us a window" is retried the same way - see
  /// [_shouldRetryAsRedirect]. Either way the customer ends up signed in; the
  /// caller is told to stand aside through [redirectInFlight], because the
  /// whole page is on its way to the provider.
  Future<bool> _signInWithPopup(
    AuthProvider provider, {
    required String Function(Object error) friendly,
  }) async {
    if (!_backendAvailable) return false;
    _clearFeedback();
    _redirectInFlight = false;
    notifyListeners();
    if (kIsWeb && isStandaloneDisplay()) {
      return _redirectSignIn(provider, friendly: friendly);
    }
    try {
      await Fb.auth.signInWithPopup(provider);
      return true;
    } catch (e) {
      if (kIsWeb && _shouldRetryAsRedirect(e)) {
        return _redirectSignIn(provider, friendly: friendly);
      }
      _message = friendly(e);
      notifyListeners();
      return false;
    }
  }

  /// Sends the browser to the provider and back. Returns true once the browser
  /// has been sent; the sign-in itself completes on the way back, where the
  /// auth-state listener picks up the session.
  Future<bool> _redirectSignIn(
    AuthProvider provider, {
    required String Function(Object error) friendly,
  }) async {
    try {
      await Fb.auth.signInWithRedirect(provider);
      _redirectInFlight = true;
      return true;
    } catch (e) {
      _message = friendly(e);
      notifyListeners();
      return false;
    }
  }

  /// Whether a failed popup attempt is worth retrying through the redirect.
  /// Only the visitor ending it themselves (and a second popup being asked for
  /// while one is already opening) is taken at face value; everything else is
  /// a popup the browser would not give us.
  static bool _shouldRetryAsRedirect(Object error) {
    if (error is! FirebaseAuthException) return true;
    switch (error.code) {
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      // These are the provider/project setup itself, not the popup: the
      // redirect would fail the same way, so it is not worth a round trip.
      case 'operation-not-allowed':
      case 'unauthorized-domain':
      case 'account-exists-with-different-credential':
        return false;
      default:
        return true;
    }
  }

  /// Registers a new customer account, sets their display name, and sends the
  /// verification email. Returns success for the account itself; secondary
  /// steps (verification mail, profile document) never fake success — a
  /// failure there becomes a [notice]/[message] on a real session.
  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    if (!_backendAvailable) return false;
    _clearFeedback();
    notifyListeners();
    final trimmedEmail = email.trim();
    final trimmedName = name.trim();
    try {
      final cred = await Fb.auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );
      // Display name on the auth user (provider-side, not a client-only flag).
      if (trimmedName.isNotEmpty) {
        try {
          await cred.user?.updateDisplayName(trimmedName);
          // Refresh the cached user so the UI shows the name immediately.
          await cred.user?.reload();
          _user = Fb.auth.currentUser;
        } catch (e) {
          debugPrint('MYCOSIX: display name not saved ($e)');
        }
      }
      // Verification email: best effort, reported honestly.
      try {
        await cred.user?.sendEmailVerification();
        _notice =
            'Account created. We sent a verification link to '
            '$trimmedEmail — tap it when you get a moment.';
      } catch (e) {
        _notice =
            'Account created. We could not send the verification email '
            'right now — you can resend it from this page.';
        debugPrint('MYCOSIX: verification email not sent ($e)');
      }
      notifyListeners();
      return true;
    } catch (e) {
      _message = Fb.friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Sends a password-reset email. Always reports success-or-failure exactly
  /// as the provider answered (no user-enumeration hints are invented).
  Future<bool> sendPasswordReset({required String email}) async {
    if (!_backendAvailable) return false;
    _clearFeedback();
    notifyListeners();
    try {
      await Fb.auth.sendPasswordResetEmail(email: email.trim());
      _notice =
          'If that email has an account, a reset link is on its way. '
          'Check your inbox (and spam folder).';
      notifyListeners();
      return true;
    } catch (e) {
      _message = Fb.friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Re-sends the verification email for the signed-in customer.
  Future<bool> resendEmailVerification() async {
    final u = _user;
    if (!_backendAvailable || u == null) return false;
    _clearFeedback();
    notifyListeners();
    try {
      await u.sendEmailVerification();
      _notice = 'Verification link re-sent to ${u.email}.';
      notifyListeners();
      return true;
    } catch (e) {
      _message = Fb.friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Refreshes the cached user (used to pick up a fresh email-verified flag
  /// after the customer tapped the link in their mail app).
  Future<void> refreshUser() async {
    if (!_backendAvailable) return;
    try {
      await Fb.auth.currentUser?.reload();
      _user = Fb.auth.currentUser;
      notifyListeners();
    } catch (_) {
      // Session unchanged; nothing to recover.
    }
  }

  Future<void> signOut() async {
    _clearFeedback();
    try {
      await Fb.auth.signOut();
    } catch (e) {
      _message = Fb.friendlyMessage(e);
      notifyListeners();
    }
  }

  /// True when this account signs in with an email + password, so closing it
  /// can be confirmed by typing that password. A Google-only account has no
  /// password to type and is confirmed with Google instead.
  bool get confirmsDeletionWithPassword =>
      _user?.providerData.any((p) => p.providerId == 'password') ?? false;

  /// The account's display email, for the confirmation wording.
  String get accountEmail => _user?.email ?? '';

  /// Closes the customer's own account.
  ///
  /// Order matters, and it is chosen so a refusal never leaves a half-deleted
  /// account behind. Firebase will only delete a sign-in that was used
  /// recently, so the customer proves who they are FIRST ([proof]); only once
  /// that is accepted is anything removed. Then the records this account owns
  /// go, and last the sign-in itself - at which point the customer is signed
  /// out, because there is no longer an account to be signed in to.
  ///
  /// Deliberately NOT deleted: past orders. They are the shop's sales records
  /// and the customer's own order history is what the shop needs to keep for
  /// accounting; the confirmation the customer reads says so plainly before
  /// they agree. Nothing here can be undone.
  Future<AccountDeletionOutcome> deleteAccount(AccountProof proof) async {
    if (!_backendAvailable) return AccountDeletionOutcome.notConfirmed;
    final u = Fb.auth.currentUser;
    if (u == null) {
      _message = 'You are not signed in.';
      notifyListeners();
      return AccountDeletionOutcome.notConfirmed;
    }
    _clearFeedback();
    notifyListeners();

    // 1. Prove it is really them. Until this succeeds, nothing is touched.
    //
    //    The Google proof is a popup, deliberately - NOT a redirect. Firebase's
    //    redirect round trip comes back through a full page load, and by the
    //    time it returns there is no way to tell a confirmation-for-deletion
    //    from an ordinary sign-in, so resuming a deletion after one could
    //    delete an account on a normal sign-in. A window that will not open is
    //    reported instead ([_deletionProofError]), never guessed at.
    try {
      if (proof.google) {
        await u.reauthenticateWithPopup(GoogleAuthProvider());
      } else {
        final email = u.email;
        if (email == null || email.isEmpty) {
          _message =
              'This account has no email address, so it cannot be confirmed '
              'here. Please contact us and we will close it for you.';
          notifyListeners();
          return AccountDeletionOutcome.notConfirmed;
        }
        await u.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: email,
            password: proof.password ?? '',
          ),
        );
      }
    } catch (e) {
      _message = _deletionProofError(e, google: proof.google);
      notifyListeners();
      return AccountDeletionOutcome.notConfirmed;
    }

    // 2. Remove the records this account owns. Each is the customer's own
    //    document, and the rules allow only its owner to delete it. A failure
    //    here is reported rather than swallowed: the sign-in is still intact,
    //    so the customer can try again.
    try {
      final uid = u.uid;
      await Future.wait(<Future<void>>[
        Fb.customers.doc(uid).delete(),
        Fb.carts.doc(uid).delete(),
        Fb.wishlists.doc(uid).delete(),
        Fb.db.collection('fcmTokens').doc(uid).delete(),
      ]);
    } catch (e) {
      _message =
          'We could not remove your saved details, so your account has been '
          'left as it is. Please try again. (${Fb.friendlyMessage(e)})';
      notifyListeners();
      return AccountDeletionOutcome.failed;
    }

    // 3. The sign-in itself. This is the point of no return: Firebase drops
    //    the session here, so the app falls back to the signed-out page.
    try {
      await u.delete();
      _clearFeedback();
      notifyListeners();
      return AccountDeletionOutcome.deleted;
    } catch (e) {
      _message =
          'Your saved details are gone, but the sign-in itself could not be '
          'removed. Please try again. (${Fb.friendlyMessage(e)})';
      notifyListeners();
      return AccountDeletionOutcome.failed;
    }
  }

  /// Turns a failed deletion confirmation into something a customer can act
  /// on. A wrong password is by far the likeliest case, and a dismissed Google
  /// window the likeliest for a Google account.
  String _deletionProofError(Object error, {required bool google}) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
        case 'invalid-credential':
          return 'That password is not correct. Nothing has been deleted.';
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return 'The Google window was closed, so nothing has been deleted.';
        case 'popup-blocked':
          return 'Your browser blocked the Google window. Allow pop-ups for '
              'this site and try again. Nothing has been deleted.';
        case 'operation-not-supported-in-this-environment':
        case 'web-storage-unsupported':
          return 'Google could not open its confirmation window here. Open '
              'mycosix.web.app in your browser - not the installed app icon - '
              'and close your account from there. Nothing has been deleted.';
        case 'requires-recent-login':
          return 'For your security please confirm once more, then try again '
              'straight away. Nothing has been deleted.';
        case 'network-request-failed':
          return 'No internet connection, so nothing has been deleted.';
        default:
          return '${Fb.friendlyMessage(error)} Nothing has been deleted.';
      }
    }
    return '${Fb.friendlyMessage(error)} Nothing has been deleted.';
  }

  void clearMessage() {
    if (_message != null || _notice != null) {
      _clearFeedback();
      notifyListeners();
    }
  }

  void _clearFeedback() {
    _message = null;
    _notice = null;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
