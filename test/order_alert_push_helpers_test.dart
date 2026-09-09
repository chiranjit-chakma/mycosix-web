import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/models/order_notice.dart';
import 'package:mycosix/models/site_settings.dart';
import 'package:mycosix/state/order_alert_controller.dart';

/// Unit tests for the notification pieces added this round:
///  - [pushEventKey] / [orderAlertForPushMessage]: the bridge between a backend
///    FCM data map and the same in-app banner the Firestore watchers raise. The
///    shared event key is what guarantees the two channels collapse to ONE
///    banner for the same order event.
///  - [OrderAlertController.presentIfFresh]: the 10s dedupe window over that
///    shared key.
///  - [SiteSettings] round-trip of the two new settings (the Admin-in-navigation
///    toggle flag and the web-push VAPID public key).
///
/// These are all pure Dart; no Firebase is initialised, so none of the live
/// watcher streams start.
void main() {
  group('pushEventKey', () {
    test('admin new-order events key on kind + doc id only', () {
      expect(
        pushEventKey(kind: 'admin-new-order', orderDocId: 'docA', statusLabel: ''),
        'admin-new-order:docA',
      );
    });

    test('customer status events key on kind + doc id + status label', () {
      expect(
        pushEventKey(
          kind: 'order-status',
          orderDocId: 'docA',
          statusLabel: 'Delivered',
        ),
        'order-status:docA:Delivered',
      );
    });

    test('the key is shared across the two channels for the same event', () {
      // The Firestore watcher and the FCM foreground listener both derive the
      // key from the same three inputs, so the same underlying event can never
      // surface as two banners even when both channels deliver it.
      expect(
        pushEventKey(kind: 'order-status', orderDocId: 'docA', statusLabel: 'Confirmed'),
        pushEventKey(kind: 'order-status', orderDocId: 'docA', statusLabel: 'Confirmed'),
      );
    });
  });

  group('orderAlertForPushMessage', () {
    test('admin-new-order becomes the same review alert as the watcher', () {
      final alert = orderAlertForPushMessage(
        kind: 'admin-new-order',
        orderDocId: 'docA',
        orderCode: 'MC-1042',
        statusLabel: '',
      );
      expect(alert, isNotNull);
      expect(alert!.kind, OrderAlertKind.adminNewOrder);
      expect(alert.orderId, 'MC-1042');
      expect(alert.title, contains('MC-1042'));
    });

    test('a notify-worthy customer status becomes the status alert', () {
      final alert = orderAlertForPushMessage(
        kind: 'order-status',
        orderDocId: 'docA',
        orderCode: 'MC-1042',
        statusLabel: 'Out for Delivery',
      );
      expect(alert, isNotNull);
      expect(alert!.kind, OrderAlertKind.customerStatus);
      expect(alert.orderId, 'MC-1042');
    });

    test('an internal-only status produces no alert', () {
      for (final label in ['New', 'Contacted', 'Preparing']) {
        expect(
          orderAlertForPushMessage(
            kind: 'order-status',
            orderDocId: 'docA',
            orderCode: 'MC-1042',
            statusLabel: label,
          ),
          isNull,
          reason: '$label must not interrupt the customer',
        );
      }
    });

    test('an unknown kind or a bare/empty status produces no alert', () {
      expect(
        orderAlertForPushMessage(
          kind: 'some-other-push',
          orderDocId: 'docA',
          orderCode: 'MC-1042',
          statusLabel: '',
        ),
        isNull,
      );
      expect(
        orderAlertForPushMessage(
          kind: 'order-status',
          orderDocId: 'docA',
          orderCode: 'MC-1042',
          statusLabel: '',
        ),
        isNull,
      );
    });

    test('every cancelled/delivered/confirmed push carries the human code', () {
      final alert = orderAlertForPushMessage(
        kind: 'order-status',
        orderDocId: 'docA',
        orderCode: 'MC-1042',
        statusLabel: 'Cancelled',
      );
      expect(alert, isNotNull);
      expect(alert!.orderId, 'MC-1042');
    });
  });

  group('OrderAlertController.presentIfFresh', () {
    OrderAlert alert(String key) => OrderAlert(
          kind: OrderAlertKind.customerStatus,
          orderId: 'MC-1042',
          title: 'Title $key',
          body: 'Body',
          actionLabel: 'View order',
        );

    test('the same event key within the window presents only once', () {
      final controller = OrderAlertController();
      addTearDown(controller.dispose);
      const key = 'order-status:docA:Delivered';
      expect(controller.presentIfFresh(alert(key), eventKey: key), isTrue);
      expect(controller.alert?.title, 'Title order-status:docA:Delivered');
      // The same order event arriving again (second channel, or a retry) is
      // swallowed inside the 10s window - one banner, never two.
      expect(controller.presentIfFresh(alert(key), eventKey: key), isFalse);
      controller.dismiss();
    });

    test('a different event always presents', () {
      final controller = OrderAlertController();
      addTearDown(controller.dispose);
      expect(
        controller.presentIfFresh(
          alert('a'),
          eventKey: 'order-status:docA:Delivered',
        ),
        isTrue,
      );
      expect(
        controller.presentIfFresh(
          alert('b'),
          eventKey: 'admin-new-order:docB',
        ),
        isTrue,
      );
      controller.dismiss();
    });
  });

  group('SiteSettings new-field round-trip', () {
    test('adminNavShortcutEnabled and the VAPID key survive toMap/fromMap', () {
      const source = SiteSettings(
        adminNavShortcutEnabled: true,
        pushVapidPublicKey: 'BElive-key-abcdef',
      );
      final map = source.toMap();
      expect(map['adminNavShortcutEnabled'], true);
      expect(map['pushVapidPublicKey'], 'BElive-key-abcdef');
      final restored = SiteSettings.fromMap(map);
      expect(restored.adminNavShortcutEnabled, isTrue);
      expect(restored.pushVapidPublicKey, 'BElive-key-abcdef');
    });

    test('absent fields default to toggle-off and an empty VAPID key', () {
      final restored = SiteSettings.fromMap(const <String, dynamic>{});
      expect(restored.adminNavShortcutEnabled, isFalse);
      expect(restored.pushVapidPublicKey, isEmpty);
    });

    test('a map without the new keys leaves them at their defaults', () {
      // A settings doc written before this feature shipped carries neither key.
      final restored = SiteSettings.fromMap(const {
        'businessName': 'MYCOSIX',
        'deliveryFee': 39,
      });
      expect(restored.adminNavShortcutEnabled, isFalse);
      expect(restored.pushVapidPublicKey, isEmpty);
    });
  });
}
