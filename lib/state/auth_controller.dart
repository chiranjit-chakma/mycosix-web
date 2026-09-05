import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/fb.dart';

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

  final bool _backendAvailable = Fb.enabled;
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
    _authSub = Fb.auth.authStateChanges().listen(
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
    _adminSub = Fb.admins
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
            _message = Fb.friendlyMessage(e);
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

  /// Sends a password-reset email for [email]. Returns success.
  Future<bool> sendPasswordReset(String email) async {
    if (!_backendAvailable) return false;
    _message = null;
    notifyListeners();
    try {
      await Fb.auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } catch (e) {
      _message = Fb.friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _message = null;
    try {
      await Fb.auth.signOut();
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
