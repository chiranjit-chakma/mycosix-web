import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/fb_admin.dart';
import '../services/display_mode.dart';

/// Where a visitor stands on the way into the admin area.
enum AdminGateStatus {
  /// Firebase is not initialised (offline / not configured). Nothing to sign
  /// in to, and the UI says so instead of faking a backend.
  backendOffline,

  /// Auth state / admin grant still loading.
  resolving,

  /// No signed-in user: show the email/password sign-in form.
  signInRequired,

  /// Signed in, but the account is not in the `admins` collection.
  notAdmin,

  /// Signed in AND authorised — render the dashboard.
  admin,
}

/// Result of submitting the admin access code to create an admins grant.
enum AdminCodeGrant {
  /// The rules verified the code server-side and created the grant; the gate
  /// rebuilds into the dashboard as soon as the grant snapshot lands.
  granted,

  /// The code was missing or wrong (or the owner has not set one yet) - the
  /// rules refused the write.
  incorrectCode,

  /// No signed-in admin-session user / backend offline: nothing to grant.
  offline,
}

/// Pure decision used by the admin gate. Kept free of Firebase so it can be
/// unit-tested without a live backend. Ordering matters: an offline backend
/// always wins, then loading, then the signed-in check, then the admin grant.
AdminGateStatus resolveAdminGate({
  required bool backendAvailable,
  required bool resolving,
  required bool signedIn,
  required bool? isAdmin,
}) {
  if (!backendAvailable) return AdminGateStatus.backendOffline;
  if (resolving) return AdminGateStatus.resolving;
  if (!signedIn) return AdminGateStatus.signInRequired;
  // Signed in: wait for the grant to be known before deciding.
  if (isAdmin == null) return AdminGateStatus.resolving;
  if (isAdmin != true) return AdminGateStatus.notAdmin;
  return AdminGateStatus.admin;
}

/// Maps a Google sign-in failure on the ADMIN session to a short, human-safe
/// message. Kept free of controller state. The "operation-not-allowed" case is
/// expected until the owner enables Google once in the Firebase console.
String friendlyAdminGoogleSignInError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'operation-not-allowed':
        return 'Google sign-in is not switched on for MYCOSIX yet - the owner '
            'needs to enable it once in the Firebase console. You can still '
            'sign in with email + password.';
      case 'popup-closed-by-user':
        return 'The Google window was closed before sign-in finished. Try '
            'again when you are ready.';
      case 'popup-blocked':
        return 'Your browser blocked the Google window. Allow pop-ups for '
            'this site and try again.';
      case 'account-exists-with-different-credential':
        return 'An account with this email already exists with a password. '
            'Sign in with your email + password instead.';
      case 'unauthorized-domain':
        return 'Google sign-in is not allowed from this web address yet. The '
            'owner needs to add it in the Firebase console under '
            'Authentication > Settings > Authorized domains.';
      case 'web-storage-unsupported':
        return 'This browser is blocking the storage Google sign-in needs '
            "(Private/Incognito windows and 'block all cookies' both do "
            'this). Use a normal window, or allow cookies for this site.';
      case 'redirect-cancelled-by-user':
        return 'The Google sign-in window was cancelled. Try again when you '
            'are ready.';
      case 'cancelled-popup-request':
        return 'Another Google sign-in was already opening. Wait a moment and '
            'try again.';
      case 'invalid-credential':
      case 'user-not-found':
        return 'Google could not confirm this account. Try again, or use '
            'email + password.';
      default:
        return FbAdmin.friendlyMessage(error);
    }
  }
  return FbAdmin.friendlyMessage(error);
}

/// Auth state + administrator authorisation.
///
/// The single source of truth for "who is signed in" is Firebase Auth. Being
/// an administrator is decided by the existence of the signed-in user's uid as
/// a document in the `admins` collection — an authorisation that lives on the
/// server, is re-checked by Firestore security rules on every write, and is
/// never derived from a client-side flag.
///
/// When the backend is unavailable, the controller simply reports so; it never
/// fabricates a session.
class AuthController extends ChangeNotifier {
  AuthController() {
    _start();
  }

  final bool _backendAvailable = FbAdmin.enabled;
  bool get backendAvailable => _backendAvailable;

  bool _resolving = true;
  bool get resolving => _resolving;

  User? _user;
  User? get user => _user;

  /// Whether an account is signed in on the ADMIN session at all. Callers that
  /// only need "is there somebody here who could hold an admin code" use this
  /// rather than [user], so it is a single, overridable seam.
  bool get hasAdminSession => _user != null;

  /// `true`/`false` once known; `null` while the grant is being watched.
  bool? _isAdmin;
  bool? get isAdmin => _isAdmin;

  /// Last friendly message (sign-in error etc.), or null.
  String? _message;
  String? get message => _message;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _adminSub;

  void _start() {
    if (!_backendAvailable) {
      _resolving = false;
      return;
    }
    // A Google sign-in may have just come back through the full-page
    // redirect flow (the installed-app path in [signInWithGoogle]).
    // Completing it here is what surfaces a failure from that round trip; a
    // successful one is already handled by the auth-state listener above.
    unawaited(_completePendingRedirect());
    _authSub = FbAdmin.auth.authStateChanges().listen(
      (u) {
        _user = u;
        _isAdmin = null;
        _resolving = true;
        _watchAdmin();
        notifyListeners();
      },
      onError: (Object e) {
        _resolving = false;
        notifyListeners();
      },
    );
  }

  void _watchAdmin() {
    _adminSub?.cancel();
    _adminSub = null;
    final u = _user;
    if (u == null) {
      _resolving = false;
      notifyListeners();
      return;
    }
    // Only the signed-in user may read their own grant document (rules).
    _adminSub = FbAdmin.admins
        .doc(u.uid)
        .snapshots()
        .listen(
          (doc) {
            _isAdmin = doc.exists;
            _resolving = false;
            notifyListeners();
          },
          onError: (Object e) {
            // Rules not deployed / offline: the safest reading is "not admin".
            _isAdmin = false;
            _resolving = false;
            _message = FbAdmin.friendlyMessage(e);
            notifyListeners();
          },
        );
  }

  /// Signs in with email + password. Returns success; failures surface as a
  /// customer-safe message on [message].
  Future<bool> signIn(String email, String password) async {
    if (!_backendAvailable) return false;
    _message = null;
    notifyListeners();
    try {
      await FbAdmin.auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return true;
    } catch (e) {
      _message = FbAdmin.friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Signs the administrator in with their Google account. A first Google
  /// sign-in also creates the account, and the account's email is what the
  /// admin code is matched against, so the address used here has to be the one
  /// an administrator set a code for.
  ///
  /// Which flow is used depends on where the app is running. In an INSTALLED
  /// app window (a home-screen PWA, on a phone or a desktop) the popup is
  /// never used: such a window has no reliable popup - it is either blocked
  /// outright or opens behind the app and is never seen again - which is what
  /// made Google sign-in look broken on a phone. Those windows go straight to
  /// Google's full-page redirect, which the browser finishes and returns from.
  /// A browser tab keeps the popup, and retries through the redirect whenever
  /// the popup fails for any reason other than the visitor deliberately
  /// closing it (the error a strict or in-app browser reports instead of
  /// popup-blocked varies far too much to enumerate).
  ///
  /// Either way the caller must not navigate away while a redirect is in
  /// flight: the auth-state listener signs the admin in when the browser comes
  /// back. Failures surface as a human-safe message on [message].
  Future<bool> signInWithGoogle() async {
    if (!_backendAvailable) return false;
    _message = null;
    notifyListeners();
    final provider = GoogleAuthProvider();
    if (kIsWeb && isStandaloneDisplay()) {
      return _redirectSignIn(provider);
    }
    try {
      await FbAdmin.auth.signInWithPopup(provider);
      return true;
    } catch (e) {
      if (kIsWeb && _shouldRetryAsRedirect(e)) {
        return _redirectSignIn(provider);
      }
      _message = friendlyAdminGoogleSignInError(e);
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

  /// Sends the browser to Google and back. Returns true once the browser has
  /// been sent; the sign-in itself completes on the way back - the auth-state
  /// listener picks it up, and [_completePendingRedirect] reports a failure.
  Future<bool> _redirectSignIn(AuthProvider provider) async {
    try {
      await FbAdmin.auth.signInWithRedirect(provider);
      return true;
    } catch (e) {
      _message = friendlyAdminGoogleSignInError(e);
      notifyListeners();
      return false;
    }
  }

  /// Completes a Google sign-in that came back through the full-page redirect.
  /// Web only - there is no redirect round trip anywhere else - and a failure
  /// is reported on the gate exactly like a popup failure would be. A launch
  /// with nothing pending is not an error, so it stays silent.
  Future<void> _completePendingRedirect() async {
    if (!kIsWeb || !_backendAvailable) return;
    try {
      await FbAdmin.auth.getRedirectResult();
    } catch (e) {
      if (e is FirebaseAuthException) {
        switch (e.code) {
          // "Nothing was pending": the ordinary case on almost every launch.
          case 'no-auth-event':
          case 'no-current-user':
            return;
        }
      }
      _message = friendlyAdminGoogleSignInError(e);
      notifyListeners();
    }
  }

  /// Sends a password-reset email for [email]. Returns success.
  Future<bool> sendPasswordReset(String email) async {
    if (!_backendAvailable) return false;
    _message = null;
    notifyListeners();
    try {
      await FbAdmin.auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } catch (e) {
      _message = FbAdmin.friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// The one message a refused code ever produces. It is deliberately the
  /// same for a wrong code, for an account no code was ever set for, and for
  /// an account signed in with a different email, so nothing about who is an
  /// administrator can be learned by trying words.
  static const String _wrongCodeMessage = 'That admin access code is not right.';

  /// Restores the server-verified secret-code entry: grants this account admin
  /// access by submitting [code]. There is exactly ONE door, and it is this
  /// account's OWN code:
  ///
  ///   * `adminCodes/{email}` - keyed by the lowercased email this account
  ///     signed in with - holds the code an administrator set for that email.
  ///     No client can read it: the rules engine alone compares a submitted
  ///     code against the stored one.
  ///   * CLAIMING that row with the right code stamps this uid onto it, and
  ///     that stamp is the only thing which then lets `admins/{uid}` be
  ///     created, with a code-free `{email, addedAt}` grant.
  ///
  /// So a code only ever works for the email it was set for, and changing a
  /// code retires the previous one immediately - the comparison is against the
  /// stored value, and the stored value is exactly what changed. There is no
  /// shared or master code and no second way in: a wrong code, an account with
  /// no code set for it, and an account signed in with a different email are
  /// all refused by the rules alike, and all surface as
  /// [AdminCodeGrant.incorrectCode] with nothing revealed.
  ///
  /// An account that is ALREADY an administrator only needs the claim to
  /// succeed (there is no grant left to create), so its own code keeps working
  /// after a fresh sign-in. On success the admin grant snapshot watched here
  /// flips to exists -> the gate rebuilds into the dashboard without any
  /// further code.
  Future<AdminCodeGrant> grantAdminWithCode(String code) async {
    if (!_backendAvailable) return AdminCodeGrant.offline;
    final u = _user;
    if (u == null) return AdminCodeGrant.offline;
    final c = code.trim();
    if (c.isEmpty) return AdminCodeGrant.incorrectCode;
    final email = (u.email ?? '').trim().toLowerCase();
    if (email.isEmpty) return AdminCodeGrant.incorrectCode;

    // The one door. Reading adminCodes is denied to every client, so whether a
    // code exists for this email is discovered by ATTEMPTING the claim: it
    // only succeeds when a row exists for this email, the submitted code
    // matches the stored one, and this uid may stamp itself onto it.
    try {
      await FbAdmin.adminCodes.doc(email).update({
        'code': c,
        'uid': u.uid,
        'grantedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _message = _wrongCodeMessage;
      notifyListeners();
      return AdminCodeGrant.incorrectCode;
    }

    // Already an administrator: the claim above was the whole check, and the
    // grant must not be rewritten (client writes to admins/{uid} are denied).
    if (_isAdmin == true) return AdminCodeGrant.granted;

    try {
      await FbAdmin.admins.doc(u.uid).set({
        'email': email,
        'addedAt': FieldValue.serverTimestamp(),
      });
      return AdminCodeGrant.granted;
    } catch (_) {
      // The claim landed but the grant create was refused - most likely this
      // account was already an administrator and the watched snapshot had not
      // caught up yet. Either way, re-submitting re-claims (the rules allow a
      // repeat by the same uid), so this is never a dead end.
      if (_isAdmin == true) return AdminCodeGrant.granted;
      _message = _wrongCodeMessage;
      notifyListeners();
      return AdminCodeGrant.incorrectCode;
    }
  }

  Future<void> signOut() async {
    _message = null;
    try {
      await FbAdmin.auth.signOut();
    } catch (_) {
      // Nothing to recover here; the dashboard stays until state updates.
    }
  }

  void clearMessage() {
    if (_message != null) {
      _message = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _adminSub?.cancel();
    super.dispose();
  }
}
