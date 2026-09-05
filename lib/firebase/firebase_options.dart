import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase configuration for the existing MYCOSIX project (project id:
/// `mycosix`). These values are the public web-app configuration — the same
/// numbers the FlutterFire CLI would generate for `flutterfire configure`.
///
/// Only web is configured for Part 2. No secret ever belongs here: an API key
/// in a web client is public by nature, which is why security is enforced by
/// Firestore rules + the trusted backend, never by hiding this file.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'MYCOSIX Part 2 configures Firebase for web only. '
      'Other platforms are not configured in this build.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBvqscwzhutRNOuetbOWoPreO7ftRuL9L4',
    appId: '1:578755322711:web:8c5e27f0a3399549da9412',
    messagingSenderId: '578755322711',
    projectId: 'mycosix',
    authDomain: 'mycosix.firebaseapp.com',
    storageBucket: 'mycosix.firebasestorage.app',
    measurementId: 'G-37T65858QG',
  );
}
