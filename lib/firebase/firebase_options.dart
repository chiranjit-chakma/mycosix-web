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
    // This MUST stay `mycosix.firebaseapp.com`. It is not a preference; it is
    // the one value Google will accept for this project's sign-in.
    //
    // authDomain is where the sign-in popup is served from AND the host Google
    // is told to send the answer back to (the OAuth `redirect_uri`, always
    // `https://<authDomain>/__/auth/handler`). That address has to be listed on
    // the project's OAuth client (Google Cloud console -> APIs & Services ->
    // Credentials -> the Web client), and the client only lists
    // `mycosix.firebaseapp.com/__/auth/handler`. Pointing authDomain at
    // `mycosix.web.app` therefore made Google refuse every sign-in with
    // "Access blocked: This app's request is invalid / Error 400:
    // redirect_uri_mismatch" - measured, and named by Google, on 2026-09-10.
    // Adding the web.app address to that OAuth client is the only way the
    // web.app domain could ever be used, and that is a Google Cloud console
    // change, not a code change.
    authDomain: 'mycosix.firebaseapp.com',
    storageBucket: 'mycosix.firebasestorage.app',
    measurementId: 'G-37T65858QG',
  );
}
