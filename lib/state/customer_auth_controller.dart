import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/fb.dart';
import 'cart_sync_controller.dart';

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
String friendlyGoogleSignInError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'operation-not-allowed':
        return 'Google sign-in is not switched on for MYCOSIX yet - the '
            'owner needs to enable it once in the Firebase console. You can '
            'still sign in with email + password.';
      case 'popup-closed-by-user':
        return 'The Google window was closed before sign-in finished. '
            'Try again when you are ready.';
      case 'popup-blocked':
        return 'Your browser blocked the Google window. Allow pop-ups for '
            'this site and try again.';
      case 'account-exists-with-different-credential':
        return 'An account with this email already exists with a password. '
            'Sign in with your email + password instead.';
      case 'invalid-credential':
      case 'user-not-found':
        return 'Google could not confirm this account. Try again, or use '
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

  StreamSubscription<User?>? _authSub;

  void _start() {
    if (!_backendAvailable) {
      _resolving = false;
      return;
    }
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
  Future<bool> signInWithGoogle() async {
    if (!_backendAvailable) return false;
    _clearFeedback();
    notifyListeners();
    try {
      await Fb.auth.signInWithPopup(GoogleAuthProvider());
      return true;
    } catch (e) {
      _message = friendlyGoogleSignInError(e);
      notifyListeners();
      return false;
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
        _notice = 'Account created. We sent a verification link to '
            '$trimmedEmail — tap it when you get a moment.';
      } catch (e) {
        _notice = 'Account created. We could not send the verification email '
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
      _notice = 'If that email has an account, a reset link is on its way. '
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
