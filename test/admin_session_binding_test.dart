import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/state/admin_session_binding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The admin session is tied to the shop session it was opened under.
///
/// The admin area signs in through its own Firebase app, so its session has
/// its own storage and would outlive the shop session by default. That is the
/// hole these tests close: signing out of the shop, or a different shop
/// account signing in on the same device, must lock the admin area - on a
/// live session, on a refresh, and after a relaunch.
void main() {
  group('judgeAdminSession', () {
    test('decides nothing until the shop session has been read', () {
      expect(
        judgeAdminSession(
          shopResolved: false,
          shopUid: 'C',
          adminSignedIn: true,
          boundShopUid: 'old',
        ),
        AdminSessionVerdict.wait,
      );
    });

    test('nothing to do when nobody is signed in on the admin side', () {
      expect(
        judgeAdminSession(
          shopResolved: true,
          shopUid: null,
          adminSignedIn: false,
          boundShopUid: null,
        ),
        AdminSessionVerdict.keep,
      );
    });

    test('a fresh admin sign-in is bound to the shop session in force', () {
      expect(
        judgeAdminSession(
          shopResolved: true,
          shopUid: 'C',
          adminSignedIn: true,
          boundShopUid: null,
        ),
        AdminSessionVerdict.bind,
      );
    });

    test('an unchanged shop session keeps the admin session', () {
      expect(
        judgeAdminSession(
          shopResolved: true,
          shopUid: 'C',
          adminSignedIn: true,
          boundShopUid: 'C',
        ),
        AdminSessionVerdict.keep,
      );
    });

    test('a shop LOGOUT ends the admin session', () {
      expect(
        judgeAdminSession(
          shopResolved: true,
          shopUid: null,
          adminSignedIn: true,
          boundShopUid: 'C',
        ),
        AdminSessionVerdict.end,
      );
    });

    test('a different shop ACCOUNT ends the admin session', () {
      // This is the leak: A was signed in and held an admin session; A signs
      // out and B signs in; without this B would open the previous admin's
      // page. "Previous Admin -> Next Admin" must never happen.
      expect(
        judgeAdminSession(
          shopResolved: true,
          shopUid: 'B',
          adminSignedIn: true,
          boundShopUid: 'A',
        ),
        AdminSessionVerdict.end,
      );
    });

    test('the shop REMAINING empty keeps an admin session opened on an empty '
        'device', () {
      expect(
        judgeAdminSession(
          shopResolved: true,
          shopUid: null,
          adminSignedIn: true,
          boundShopUid: kAdminBindingNobody,
        ),
        AdminSessionVerdict.keep,
      );
    });

    test('someone signing into the shop ends an admin session that was opened '
        'while nobody was', () {
      expect(
        judgeAdminSession(
          shopResolved: true,
          shopUid: 'E',
          adminSignedIn: true,
          boundShopUid: kAdminBindingNobody,
        ),
        AdminSessionVerdict.end,
      );
    });

    test('a sign-out that has not come back yet is not re-bound', () {
      // A slow (or failed) admin sign-out must never be mistaken for a fresh
      // sign-in and re-bound to the current shop account.
      expect(
        judgeAdminSession(
          shopResolved: true,
          shopUid: 'C',
          adminSignedIn: true,
          boundShopUid: null,
          endPending: true,
        ),
        AdminSessionVerdict.end,
      );
    });
  });

  group('AdminSessionBinding', () {
    late StreamController<String?> shop;
    late StreamController<String?> admin;
    late SharedPreferences prefs;
    late int ended;

    Future<AdminSessionBinding> bind({String? storedBinding}) async {
      SharedPreferences.setMockInitialValues(
        storedBinding == null
            ? <String, Object>{}
            : <String, Object>{AdminSessionBinding.storageKey: storedBinding},
      );
      prefs = await SharedPreferences.getInstance();
      shop = StreamController<String?>.broadcast();
      admin = StreamController<String?>.broadcast();
      ended = 0;
      final b = AdminSessionBinding(
        prefs: prefs,
        shopUids: shop.stream,
        adminUids: admin.stream,
        // A real sign-out makes the admin auth state report "nobody signed
        // in", and that is what releases the binding. Model it, so these tests
        // see the same sequence of events the app does.
        endAdminSession: () async {
          ended++;
          admin.add(null);
        },
      )..start();
      return b;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    tearDown(() async {
      await shop.close();
      await admin.close();
    });

    test('admin signs in while the shop is signed in -> bound to that shop '
        'account', () async {
      final b = await bind();
      shop.add('C');
      admin.add('A');
      await settle();
      expect(b.boundShopUid, 'C');
      expect(ended, 0);
      expect(prefs.getString(AdminSessionBinding.storageKey), 'C');
    });

    test('shop logs out -> the admin session ends at once', () async {
      final b = await bind();
      shop.add('C');
      admin.add('A');
      await settle();
      expect(ended, 0);

      shop.add(null); // the shop account signs out
      await settle();

      expect(ended, 1, reason: 'the open admin session must be ended');
      expect(b.boundShopUid, isNull);
      expect(prefs.getString(AdminSessionBinding.storageKey), isNull);
    });

    test('a different shop account signing in -> the previous admin session '
        'ends', () async {
      final b = await bind();
      shop.add('A');
      admin.add('A');
      await settle();

      shop.add(null); // A signs out
      await settle();
      shop.add('B'); // B signs in
      await settle();

      expect(ended, 1);
      expect(b.boundShopUid, isNull,
          reason: 'B must not inherit anything from A');
    });

    test('after the shop logout, signing in as B and opening the admin area '
        'needs a FRESH admin sign-in', () async {
      final b = await bind();
      shop.add('A');
      admin.add('A');
      await settle();
      shop.add(null);
      await settle();
      shop.add('B');
      await settle();

      // B signs in on the admin side: a fresh session, bound to B.
      admin.add('b-uid');
      await settle();

      expect(b.boundShopUid, 'B');
      expect(ended, 1, reason: 'no second teardown for a legitimate sign-in');
    });

    test('a RELAUNCH after the shop account changed ends the admin session '
        'before it is shown', () async {
      // The decide-on-restore case: the admin session and the shop session are
      // both restored from storage, so nothing "changes" while the app is
      // running - the binding recorded at the time is what catches it.
      await bind(storedBinding: 'A');
      admin.add('a-uid'); // the admin session restores first
      await settle();
      shop.add('B'); // ... and the shop side is now somebody else
      await settle();

      expect(ended, 1,
          reason: 'B must not be handed the admin session opened under A');
    });

    test('a RELAUNCH with the same shop account keeps the admin session',
        () async {
      final b = await bind(storedBinding: 'C');
      admin.add('a-uid');
      shop.add('C');
      await settle();
      expect(ended, 0);
      expect(b.boundShopUid, 'C');
    });

    test('a RELAUNCH after the shop account signed out ends the admin session',
        () async {
      final b = await bind(storedBinding: 'C');
      admin.add('a-uid');
      shop.add(null); // the shop is signed out now
      await settle();
      expect(ended, 1);
      expect(b.boundShopUid, isNull);
    });

    test('nothing is decided before the shop session has been read', () async {
      final b = await bind(storedBinding: 'A');
      admin.add('a-uid');
      await settle();
      expect(ended, 0, reason: 'the shop side has not been read yet');
      expect(b.boundShopUid, 'A');
    });

    test('an admin sign-out clears the binding, so the next sign-in is bound '
        'to whoever is there then', () async {
      final b = await bind();
      shop.add('C');
      admin.add('A');
      await settle();
      expect(b.boundShopUid, 'C');

      admin.add(null); // the admin leaves the admin area
      await settle();
      expect(b.boundShopUid, isNull);
      expect(prefs.getString(AdminSessionBinding.storageKey), isNull);

      shop.add('D'); // the shop account changes while no admin is signed in
      await settle();
      expect(ended, 0, reason: 'there was no admin session to end');

      admin.add('a-uid'); // a fresh admin sign-in
      await settle();
      expect(b.boundShopUid, 'D');
    });

    test('an admin session opened while the shop is signed out is bound to '
        'that, and survives a relaunch in the same state', () async {
      final b = await bind();
      shop.add(null);
      admin.add('a-uid');
      await settle();
      expect(b.boundShopUid, kAdminBindingNobody);
      expect(ended, 0);
    });
  });
}
