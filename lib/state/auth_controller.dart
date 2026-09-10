import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/fb_admin.dart';

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

  /// Signs the administrator in with their Google account (a popup window). A
  /// first Google sign-in also creates the account. When the browser blocks
  /// the popup the same provider is retried through the full-page redirect and
  /// the auth-state listener signs the admin in when the browser returns, so
  /// the caller must not navigate away meanwhile. Google must be switched on
  /// for the project once in the Firebase console; failures surface as a
  /// human-safe message on [message].
  Future<bool> signInWithGoogle() async {
    if (!_backendAvailable) return false;
    _message = null;
    notifyListeners();
    try {
      await FbAdmin.auth.signInWithPopup(GoogleAuthProvider());
      return true;
    } catch (e) {
      if (kIsWeb && e is FirebaseAuthException && e.code == 'popup-blocked') {
        try {
          await FbAdmin.auth.signInWithRedirect(GoogleAuthProvider());
          return true;
        } catch (redirectError) {
          _message = friendlyAdminGoogleSignInError(redirectError);
          notifyListeners();
          return false;
        }
      }
      _message = friendlyAdminGoogleSignInError(e);
      notifyListeners();
      return false;
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

  /// Restores the server-verified secret-code entry: grants this account admin
  /// access by submitting [code]. Two server-verified doors exist, tried in
  /// order:
  ///
  /// 1. A per-email invite (the Admins manager): if this email has an
  ///    `adminCodes` row, CLAIMING it with the right code stamps this uid onto
  ///    that row, then the `admins/{uid}` create is verified against the stamp
  ///    and records a code-free `{email, addedAt}` grant. A wrong per-email
  ///    code - or no invite - changes nothing and falls through to ...
  /// 2. ... the owner-set admin access code (the master code): create
  ///    `admins/{uid}` = `{code}`; the rules compare the code against the
  ///    unreadable secrets/adminGate document and refuse unless it matches
  ///    exactly and the write is the submitter's own uid with exactly one
  ///    field.
  ///
  /// Either way a wrong code (or no code configured yet) surfaces as
  /// [AdminCodeGrant.incorrectCode] and leaves the account non-admin. On
  /// success the admin grant snapshot watched here flips to exists -> the gate
  /// rebuilds into the dashboard without any further code.
  Future<AdminCodeGrant> grantAdminWithCode(String code) async {
    if (!_backendAvailable) return AdminCodeGrant.offline;
    final u = _user;
    if (u == null) return AdminCodeGrant.offline;
    final c = code.trim();
    if (c.isEmpty) return AdminCodeGrant.incorrectCode;
    final email = (u.email ?? '').trim().toLowerCase();
    var claimed = false;
    if (email.isNotEmpty) {
      // Door 1: per-email invite. Reading adminCodes is denied to every
      // client, so whether a row exists is discovered by attempting the claim:
      // it only succeeds when a row exists for this email, the submitted code
      // matches it, and this uid may stamp itself onto it.
      try {
        await FbAdmin.adminCodes.doc(email).update({
          'code': c,
          'uid': u.uid,
          'grantedAt': FieldValue.serverTimestamp(),
        });
        claimed = true;
      } catch (_) {
        claimed = false;
      }
      if (claimed) {
        try {
          await FbAdmin.admins.doc(u.uid).set({
            'email': email,
            'addedAt': FieldValue.serverTimestamp(),
          });
          return AdminCodeGrant.granted;
        } catch (_) {
          // The claim landed but the grant create was refused (e.g. a transient
          // network failure). Re-submitting re-claims (rules allow uid == self)
          // so this is never a dead end; fall through to door 2 this attempt.
          claimed = false;
        }
      }
    }
    // Door 2: owner-set master code.
    try {
      await FbAdmin.admins.doc(u.uid).set({'code': c});
      return AdminCodeGrant.granted;
    } catch (_) {
      _message = 'That admin access code is not right.';
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
