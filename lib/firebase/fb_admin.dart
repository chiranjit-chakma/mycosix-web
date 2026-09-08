import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'fb.dart';

/// Admin-area Firebase access point - a SECOND, named Firebase app, so the
/// admin's sign-in and sign-out live on their own auth session that can never
/// overwrite, replace or observe the customer session of the default app.
/// The two sides of the app stay completely separate accounts even in one
/// browser tab: the customer keeps using the default app ([Fb]) and the
/// admin area uses this one.
///
/// Everything else mirrors [Fb]: [enabled] flips to true only after
/// [Firebase.initializeApp] succeeds for the admin app, every caller checks
/// it and renders a friendly state instead of assuming the backend exists,
/// and authorisation is enforced by the same Firestore security rules - both
/// apps talk to the same project, so the admin identity on a request is still
/// checked against the `admins/{uid}` collection exactly as before.
class FbAdmin {
  FbAdmin._();

  /// Name of the named Firebase app that hosts the admin session. Distinct
  /// from the default app, so the browser keeps two fully independent auth
  /// sessions: the customer's and the admin's. Auth persistence keys are
  /// per-app, so signing in as admin here never logs the customer out (and
  /// vice versa), and no page on the customer side can ever observe the
  /// admin identity.
  static const String appName = 'mycosix-admin';

  static bool enabled = false;

  static FirebaseApp? _app;

  /// Binds the initialised admin [app]. Called once at startup right after
  /// [Fb] came up; [enabled] stays false if it never happens (offline /
  /// not configured), and the admin gate reports so instead of faking a
  /// backend.
  static void attach(FirebaseApp app) {
    _app = app;
    enabled = true;
  }

  static FirebaseFirestore get db => FirebaseFirestore.instanceFor(app: _app!);

  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: _app!);

  // Collections used by the admin area - same project, same document
  // structure, same rules as [Fb]. Only the auth identity on the request
  // (and therefore who the rules see as the caller) is scoped to this app.
  static CollectionReference<Map<String, dynamic>> get products =>
      db.collection('products');
  static CollectionReference<Map<String, dynamic>> get orders =>
      db.collection('orders');
  static CollectionReference<Map<String, dynamic>> get admins =>
      db.collection('admins');
  static CollectionReference<Map<String, dynamic>> get siteConfig =>
      db.collection('siteConfig');
  static CollectionReference<Map<String, dynamic>> get customers =>
      db.collection('customers');
  static CollectionReference<Map<String, dynamic>> get carts =>
      db.collection('carts');
  static CollectionReference<Map<String, dynamic>> get wishlists =>
      db.collection('wishlists');
  static CollectionReference<Map<String, dynamic>> get batches =>
      db.collection('batches');
  static CollectionReference<Map<String, dynamic>> get orderRequests =>
      db.collection('orderRequests');
  static CollectionReference<Map<String, dynamic>> get inventoryMovements =>
      db.collection('inventoryMovements');

  /// Maps a Firebase/network failure to a short, human-safe message. The
  /// vocabulary is shared with the customer side, so this simply delegates.
  static String friendlyMessage(Object error) => Fb.friendlyMessage(error);
}
