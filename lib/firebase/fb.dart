import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Central Firebase access point for MYCOSIX Part 2.
///
/// [enabled] flips to true only after [Firebase.initializeApp] succeeds. Every
/// caller must check it and render a friendly state instead of assuming the
/// backend exists — that keeps the customer site usable even while Firebase is
/// unreachable or before rules are deployed.
///
/// All read/write authorisation is enforced by Firestore security rules and the
/// trusted Cloud Functions — never by this file.
class Fb {
  Fb._();

  static bool enabled = false;

  static FirebaseFirestore get db => FirebaseFirestore.instance;

  static FirebaseAuth get auth => FirebaseAuth.instance;

  // Collections used by MYCOSIX. Document structure is defined in the
  // Firestore rules and the repository/map files that read them.
  static CollectionReference<Map<String, dynamic>> get products =>
      db.collection('products');
  static CollectionReference<Map<String, dynamic>> get orders =>
      db.collection('orders');
  static CollectionReference<Map<String, dynamic>> get admins =>
      db.collection('admins');
  static CollectionReference<Map<String, dynamic>> get siteConfig =>
      db.collection('siteConfig');

  // Zero-budget production data collections. All are admin-only under the
  // security rules: customers can never read or write them.
  static CollectionReference<Map<String, dynamic>> get batches =>
      db.collection('batches');
  static CollectionReference<Map<String, dynamic>> get orderRequests =>
      db.collection('orderRequests');
  static CollectionReference<Map<String, dynamic>> get inventoryMovements =>
      db.collection('inventoryMovements');

  /// Maps a Firebase/network failure to a short, human-safe message. Customers
  /// must never see stack traces or Firebase internals.
  static String friendlyMessage(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'invalid-login-credentials':
        case 'user-not-found':
          return 'That email or password is not correct.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'network-request-failed':
          return 'No internet connection. Please try again.';
        case 'operation-not-allowed':
          return 'Email/password sign-in is not enabled for this project yet.';
        default:
          return 'Sign-in failed. Please try again.';
      }
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to do that.';
        case 'unavailable':
        case 'network-request-failed':
          return 'The connection to our servers failed. Please try again.';
        case 'not-found':
          return 'That record could not be found.';
        default:
          return 'Something went wrong. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
