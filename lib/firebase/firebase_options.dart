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
    // The sign-in popup must be served from the SAME site as the app.
    //
    // This used to be `mycosix.firebaseapp.com`, which is a different site
    // from `mycosix.web.app`, so the sign-in popup ran cross-site. Browsers
    // now block or partition storage between sites (Chrome's third-party
    // cookie restrictions, Safari's ITP), and the popup hands the finished
    // sign-in back through exactly that storage - so Google sign-in worked
    // when it was first set up and then quietly stopped, which is precisely
    // what the owner reported. Firebase Hosting serves the sign-in handler at
    // /__/auth/* on our own domain (reserved paths, not part of the app), and
    // mycosix.web.app is already in the project's Authorized domains, so
    // pointing authDomain here makes the popup same-origin and immune to
    // cross-site storage blocking. It also works for local development, where
    // the page is on localhost (also an authorized domain) and the popup is
    // cross-site exactly as before.
    authDomain: 'mycosix.web.app',
    storageBucket: 'mycosix.firebasestorage.app',
    measurementId: 'G-37T65858QG',
  );
}
