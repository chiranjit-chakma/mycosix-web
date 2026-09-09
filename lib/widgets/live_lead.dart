import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../firebase/fb.dart';
import 'editorial.dart';

/// Resolves an optional content override against a bundled fallback: a blank
/// or missing field keeps the built-in copy, a present value is trimmed. Used
/// by every content-driven widget so the rule is tested once.
String contentPick(
  Map<String, dynamic>? m,
  String key,
  String fallback,
) {
  final v = m?[key];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  return fallback;
}

/// [contentPick] for an optional field: blank/missing -> null stays null
/// (e.g. a feature's `bodyExtra` line simply not shown).
String? contentPickOpt(Map<String, dynamic>? m, String key, String? fallback) {
  final v = m?[key];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  return fallback;
}

/// A hero-lead that the admin can override from the `content` collection.
///
/// The Journey and Farm pages read their opening hero copy from Firestore when
/// Firebase is available and a matching content document exists; otherwise they
/// render exactly the built-in copy passed in (Firebase unreachable, offline,
/// widget tests, or before an admin adds a record). Overriding only the fields
/// the stored document actually carries keeps layout stable — the same
/// [MxPageHero] is used either way.
///
/// Document shape: `content/{docId}` with optional string fields
/// `overline`, `title`, `body`. A blank/missing field falls back to the
/// bundled value for that slot, so an admin can update just the line they care
/// about.
class LiveLead extends StatelessWidget {
  const LiveLead({
    super.key,
    required this.docId,
    required this.overline,
    required this.title,
    required this.body,
    required this.image,
  });

  /// Content document id that may override this lead (e.g. 'journey-hero').
  final String docId;

  /// Bundled fallback copy (also the initial render).
  final String overline;
  final String title;
  final String body;
  final String image;

  @override
  Widget build(BuildContext context) {
    if (!Fb.enabled) {
      return MxPageHero(
        overline: overline,
        title: title,
        body: body,
        image: image,
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Fb.db.collection('content').doc(docId).snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data();
        return MxPageHero(
          overline: contentPick(m, 'overline', overline),
          title: contentPick(m, 'title', title),
          body: contentPick(m, 'body', body),
          image: image,
        );
      },
    );
  }
}

/// Reads one content document and resolves its optional text fields against
/// bundled fallbacks, so a blank/missing field keeps today's copy. When
/// Firebase is unavailable (offline, widget tests) it passes the fallbacks
/// straight through and never opens a stream.
class LiveEditorial extends StatelessWidget {
  const LiveEditorial({
    super.key,
    required this.docId,
    required this.overline,
    required this.title,
    required this.body,
    this.bodyExtra,
    required this.builder,
  });

  final String docId;
  final String overline;
  final String title;
  final String body;
  final String? bodyExtra;
  final Widget Function(String overline, String title, String body,
          String? bodyExtra)
      builder;

  @override
  Widget build(BuildContext context) {
    if (!Fb.enabled) {
      return builder(overline, title, body, bodyExtra);
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Fb.db.collection('content').doc(docId).snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data();
        return builder(
          contentPick(m, 'overline', overline),
          contentPick(m, 'title', title),
          contentPick(m, 'body', body),
          contentPickOpt(m, 'bodyExtra', bodyExtra),
        );
      },
    );
  }
}

